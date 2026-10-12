import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/db/database.dart';
import 'edb_budget.dart';

/// RapidAPI host for ExerciseDB V2 (AscendAPI).
const edbHost = 'edb-with-videos-and-images-by-ascendapi.p.rapidapi.com';

/// From `--dart-define-from-file=config/secrets.json` (git-ignored). Never logged or printed.
const edbApiKey = String.fromEnvironment('EDB_RAPIDAPI_KEY');

class EdbException implements Exception {
  const EdbException(this.status, this.code, [this.message = '']);

  /// HTTP status (0 when no request was made).
  final int status;

  /// AscendAPI error code (UNAUTHORIZED, TOO_MANY_REQUESTS…) or ours (NO_KEY, BUDGET, NETWORK).
  final String code;
  final String message;

  /// The fallbacks the exercise page takes silently.
  bool get fallsBack => status == 401 || status == 403 || status == 429 || code == 'BUDGET' || code == 'NO_KEY' || code == 'NETWORK';

  @override
  String toString() => 'EdbException($status $code${message.isEmpty ? '' : ': $message'})';
}

class EdbSearchHit {
  const EdbSearchHit({required this.exerciseId, required this.name, this.imageUrl});
  final String exerciseId;
  final String name;
  final String? imageUrl;

  factory EdbSearchHit.fromJson(Map<String, dynamic> j) => EdbSearchHit(
        exerciseId: j['exerciseId'] as String,
        name: j['name'] as String,
        imageUrl: (j['imageUrl'] as String?)?.isEmpty ?? true ? null : j['imageUrl'] as String,
      );
}

/// GET /api/v1/exercises/{id}. Media URLs and text are session data (see EdbCache): they rotate every
/// Monday 00:00 UTC and may only be persisted when the plan allows caching.
class EdbExercise {
  const EdbExercise({
    required this.exerciseId,
    required this.name,
    this.equipments = const [],
    this.bodyParts = const [],
    this.targetMuscles = const [],
    this.secondaryMuscles = const [],
    this.overview,
    this.instructions = const [],
    this.exerciseTips = const [],
    this.variations = const [],
    this.relatedExerciseIds = const [],
    this.videoUrl,
    this.imageUrl,
    this.imageUrls = const {},
  });

  final String exerciseId;
  final String name;
  final List<String> equipments;
  final List<String> bodyParts;
  final List<String> targetMuscles;
  final List<String> secondaryMuscles;
  final String? overview;
  final List<String> instructions;
  final List<String> exerciseTips;
  final List<String> variations;
  final List<String> relatedExerciseIds;
  final String? videoUrl;
  final String? imageUrl;

  /// "360p" | "480p" | "720p" | "1080p" → URL.
  final Map<String, String> imageUrls;

  static List<String> _list(Object? v) => [for (final x in (v as List<dynamic>? ?? const [])) '$x'];

  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

  factory EdbExercise.fromJson(Map<String, dynamic> j) => EdbExercise(
        exerciseId: j['exerciseId'] as String,
        name: j['name'] as String,
        equipments: _list(j['equipments']),
        bodyParts: _list(j['bodyParts']),
        targetMuscles: _list(j['targetMuscles']),
        secondaryMuscles: _list(j['secondaryMuscles']),
        overview: _str(j['overview']),
        instructions: _list(j['instructions']),
        exerciseTips: _list(j['exerciseTips']),
        variations: _list(j['variations']),
        relatedExerciseIds: _list(j['relatedExerciseIds']),
        videoUrl: _str(j['videoUrl']),
        imageUrl: _str(j['imageUrl']),
        imageUrls: {
          for (final e in ((j['imageUrls'] as Map<String, dynamic>?) ?? const {}).entries)
            if (e.value is String && (e.value as String).isNotEmpty) e.key: e.value as String,
        },
      );

  Map<String, Object?> toJson() => {
        'exerciseId': exerciseId,
        'name': name,
        'equipments': equipments,
        'bodyParts': bodyParts,
        'targetMuscles': targetMuscles,
        'secondaryMuscles': secondaryMuscles,
        'overview': overview,
        'instructions': instructions,
        'exerciseTips': exerciseTips,
        'variations': variations,
        'relatedExerciseIds': relatedExerciseIds,
        'videoUrl': videoUrl,
        'imageUrl': imageUrl,
        'imageUrls': imageUrls,
      };
}

/// The two calls the app makes. Tests use a fake; nothing in CI hits the network.
abstract interface class EdbApi {
  Future<List<EdbSearchHit>> search(String query);
  Future<EdbExercise> exercise(String exerciseId);
}

/// One line of the V2 debug log: calls, fallbacks and errors (never the key).
class EdbLogEntry {
  const EdbLogEntry(this.at, this.kind, this.detail);
  final DateTime at;
  final String kind; // call | fallback | error | warn
  final String detail;

  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 'kind': kind, 'detail': detail};

  factory EdbLogEntry.fromJson(Map<String, dynamic> j) =>
      EdbLogEntry(DateTime.parse(j['at'] as String), j['kind'] as String, j['detail'] as String);
}

/// Persists the budget and the debug log in app settings.
class EdbBudgetStore {
  EdbBudgetStore(this._db);
  final AppDatabase _db;

  static const budgetKey = 'edb_budget';
  static const logKey = 'edb_log';
  static const int maxLog = 100;

  Future<EdbBudget> load(DateTime now) async => EdbBudget.decode(await _db.getSetting(budgetKey), now);

  Future<void> save(EdbBudget b) => _db.putSetting(budgetKey, b.encode());

  Future<List<EdbLogEntry>> log() async {
    final raw = await _db.getSetting(logKey);
    if (raw == null) return const [];
    return [for (final e in jsonDecode(raw) as List<dynamic>) EdbLogEntry.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> addLog(EdbLogEntry e) async {
    final all = [...await log(), e];
    final kept = all.length > maxLog ? all.sublist(all.length - maxLog) : all;
    await _db.putSetting(logKey, jsonEncode([for (final x in kept) x.toJson()]));
  }
}

/// ExerciseDB V2 over RapidAPI. Every call goes through the budget guard first and records RapidAPI's
/// rate-limit headers after; a hard stop throws EdbException('BUDGET') without touching the network.
class EdbV2Client implements EdbApi {
  EdbV2Client({required http.Client client, required this.store, String apiKey = edbApiKey, DateTime Function()? clock})
      : _http = client,
        _key = apiKey,
        _clock = clock ?? DateTime.now;

  final http.Client _http;
  final EdbBudgetStore store;
  final String _key;
  final DateTime Function() _clock;

  bool get hasKey => _key.isNotEmpty;

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final now = _clock();
    if (_key.isEmpty) throw const EdbException(0, 'NO_KEY', 'Run with --dart-define-from-file=config/secrets.json');
    final budget = await store.load(now);
    if (!budget.allows(now)) {
      await store.addLog(EdbLogEntry(now, 'fallback', 'budget hard stop (${budget.used} used) — $path'));
      throw EdbException(0, 'BUDGET', 'Monthly budget reached; V2 resumes on ${budget.resumesOn().toIso8601String().substring(0, 10)}');
    }
    final uri = Uri.https(edbHost, path, query.isEmpty ? null : query);
    http.Response res;
    try {
      res = await _http.get(uri, headers: {'X-RapidAPI-Key': _key, 'X-RapidAPI-Host': edbHost}).timeout(const Duration(seconds: 15));
    } catch (e) {
      await store.addLog(EdbLogEntry(now, 'error', 'network: $path'));
      throw EdbException(0, 'NETWORK', '$e'.replaceAll(_key, '***'));
    }
    final after = budget.record(now, headers: {for (final h in res.headers.entries) h.key.toLowerCase(): h.value});
    await store.save(after);
    final label = '${uri.path}${query.isEmpty ? '' : '?${uri.query}'} → ${res.statusCode}';
    await store.addLog(EdbLogEntry(now, res.statusCode == 200 ? 'call' : 'error', label));
    if (after.warn && !budget.warn) {
      await store.addLog(EdbLogEntry(now, 'warn', 'soft limit: ${after.used} of ${EdbBudget.planLimit} calls used this month'));
    }
    if (res.statusCode != 200) {
      String code = 'HTTP_${res.statusCode}', message = '';
      try {
        final err = (jsonDecode(res.body) as Map<String, dynamic>)['error'] as Map<String, dynamic>?;
        code = err?['code'] as String? ?? code;
        message = err?['message'] as String? ?? '';
      } catch (_) {}
      throw EdbException(res.statusCode, code, message);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  @override
  Future<List<EdbSearchHit>> search(String query) async {
    final j = await _get('/api/v1/exercises/search', {'search': query});
    return [for (final e in (j['data'] as List<dynamic>? ?? const [])) EdbSearchHit.fromJson(e as Map<String, dynamic>)];
  }

  @override
  Future<EdbExercise> exercise(String exerciseId) async {
    final j = await _get('/api/v1/exercises/${Uri.encodeComponent(exerciseId)}', const {});
    return EdbExercise.fromJson(j['data'] as Map<String, dynamic>);
  }
}
