import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../core/db/database.dart';
import '../../library/domain/exercise_info.dart';
import '../domain/media_matcher.dart';

/// Bump when the matcher or the ExerciseDB asset changes so matches are recomputed
/// (manual picks are kept).
const int mediaMatchVersion = 3; // v2: dead GIFs (HTTP 404) excluded; v3: exercises with their own V1 GIF

/// GIFs are downloaded on first view and kept for a year.
final gifCacheManager = CacheManager(Config(
  'exercise_gifs',
  stalePeriod: const Duration(days: 365),
  maxNrOfCacheObjects: 2000,
));

/// Top-level so the isolate closure captures only plain data (never the database).
List<MediaMatch> _matchAll(List<EdbExercise> edb, List<LibraryExerciseKey> keys) {
  final m = MediaMatcher(edb);
  return [for (final k in keys) m.match(k)];
}

/// Separate function so the closure's context can't include `this` (and with it the database).
Future<List<MediaMatch>> _matchInIsolate(List<EdbExercise> edb, List<LibraryExerciseKey> keys) =>
    Isolate.run(() => _matchAll(edb, keys));

class MediaRepository {
  MediaRepository(this._db);
  final AppDatabase _db;

  static const _versionKey = 'media_match_version';

  static List<EdbExercise>? _edbCache;
  static Map<String, String?>? _overridesCache;
  static MediaMatcher? _matcherCache;

  static Future<List<EdbExercise>> loadEdb() async {
    if (_edbCache != null) return _edbCache!;
    final raw = jsonDecode(await rootBundle.loadString('assets/exercisedb_v1.json')) as Map<String, dynamic>;
    return _edbCache = (raw['exercises'] as List<dynamic>)
        .map((e) => EdbExercise.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Map<String, String?>> loadOverrides() async {
    if (_overridesCache != null) return _overridesCache!;
    final raw = jsonDecode(await rootBundle.loadString('assets/media_overrides.json')) as Map<String, dynamic>;
    return _overridesCache = (raw['overrides'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String?));
  }

  static Future<MediaMatcher> matcher() async => _matcherCache ??= MediaMatcher(await loadEdb());

  static LibraryExerciseKey keyFor(ExerciseInfo e) => LibraryExerciseKey(
        id: e.id,
        name: e.name,
        equipment: e.equipment,
        primaryMuscles: e.primaryMuscles,
        secondaryMuscles: e.secondaryMuscles,
      );

  /// Matches every catalogue exercise (first launch, after a version bump, or for new custom
  /// exercises). Overrides from the asset are applied; manual picks are never overwritten.
  Future<void> ensureMatched(Map<String, ExerciseInfo> catalog, {required DateTime now}) async {
    final version = int.tryParse(await _db.getSetting(_versionKey) ?? '') ?? 0;
    final existing = {for (final r in await _db.select(_db.mediaMatches).get()) r.exerciseId: r};
    final todo = version == mediaMatchVersion
        ? catalog.values.where((e) => !existing.containsKey(e.id)).toList()
        : catalog.values.where((e) => existing[e.id]?.source != 'manual').toList();
    if (todo.isEmpty) {
      if (version != mediaMatchVersion) await _db.putSetting(_versionKey, '$mediaMatchVersion');
      return;
    }
    final edb = await loadEdb();
    final overrides = await loadOverrides();
    final keys = [for (final e in todo) keyFor(e)];
    // Matching all 876 exercises takes a few hundred ms; keep it off the UI thread.
    final results = await _matchInIsolate(edb, keys);
    final byId = {for (final e in edb) e.id: e};
    await _db.batch((b) {
      for (final r in results) {
        final MediaMatchesCompanion row;
        final own = catalog[r.exerciseId]?.edbV1Id;
        if (!overrides.containsKey(r.exerciseId) && own != null && byId.containsKey(own)) {
          // The exercise came from (or was merged with) this V1 entry: its own GIF, no guessing.
          final e = byId[own]!;
          row = MediaMatchesCompanion.insert(
            exerciseId: r.exerciseId,
            edbId: Value(e.id),
            edbName: Value(e.name),
            gifUrl: Value(e.gifUrl),
            confidence: const Value(1),
            source: const Value('library'),
            updatedAt: now,
          );
        } else if (overrides.containsKey(r.exerciseId)) {
          final e = byId[overrides[r.exerciseId]];
          row = MediaMatchesCompanion.insert(
            exerciseId: r.exerciseId,
            edbId: Value(e?.id),
            edbName: Value(e?.name),
            gifUrl: Value(e?.gifUrl),
            confidence: const Value(1),
            source: const Value('override'),
            updatedAt: now,
          );
        } else {
          final best = r.best;
          final usable = best != null && r.confidence != MatchConfidence.none;
          row = MediaMatchesCompanion.insert(
            exerciseId: r.exerciseId,
            edbId: Value(usable ? best.edb.id : null),
            edbName: Value(usable ? best.edb.name : null),
            gifUrl: Value(usable ? best.edb.gifUrl : null),
            confidence: Value(best?.score ?? 0),
            updatedAt: now,
          );
        }
        b.insert(_db.mediaMatches, row, onConflict: DoUpdate((_) => row));
      }
    });
    await _db.putSetting(_versionKey, '$mediaMatchVersion');
  }

  Stream<MediaMatchRow?> watchMatch(String exerciseId) =>
      (_db.select(_db.mediaMatches)..where((t) => t.exerciseId.equals(exerciseId))).watchSingleOrNull();

  Stream<List<MediaMatchRow>> watchAll() => _db.select(_db.mediaMatches).watch();

  Future<MediaMatchRow?> match(String exerciseId) =>
      (_db.select(_db.mediaMatches)..where((t) => t.exerciseId.equals(exerciseId))).getSingleOrNull();

  /// Debug screen: pick a candidate (or "none") by hand. Survives re-matching.
  Future<void> setManual(String exerciseId, EdbExercise? e, {required DateTime now}) {
    final row = MediaMatchesCompanion.insert(
      exerciseId: exerciseId,
      edbId: Value(e?.id),
      edbName: Value(e?.name),
      gifUrl: Value(e?.gifUrl),
      confidence: const Value(1),
      source: const Value('manual'),
      updatedAt: now,
    );
    return _db.into(_db.mediaMatches).insert(row, onConflict: DoUpdate((_) => row));
  }

  /// Asset overrides + manual picks, in the `media_overrides.json` format, ready to paste.
  Future<String> exportOverrides() async {
    final rows = await (_db.select(_db.mediaMatches)..where((t) => t.source.isIn(['override', 'manual']))).get();
    final map = {for (final r in rows..sort((a, b) => a.exerciseId.compareTo(b.exerciseId))) r.exerciseId: r.edbId};
    return const JsonEncoder.withIndent('  ').convert({'schema_version': 1, 'overrides': map});
  }

  /// Downloads (once) the GIFs for the given exercises, e.g. everything in the routines.
  Future<int> prefetch(Iterable<String> exerciseIds) async {
    var fetched = 0;
    for (final id in exerciseIds.toSet()) {
      final url = (await match(id))?.gifUrl;
      if (url == null) continue;
      try {
        if (await gifCacheManager.getFileFromCache(url) == null) {
          await gifCacheManager.downloadFile(url);
          fetched++;
        }
      } catch (e) {
        debugPrint('GIF prefetch failed for $id: $e');
      }
    }
    return fetched;
  }
}
