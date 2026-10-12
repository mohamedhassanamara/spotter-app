import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/db/database.dart';
import '../../../library/domain/exercise_info.dart';
import '../../domain/edb_v2_mapping.dart';
import 'edb_client.dart';

/// Result of mapping a batch of exercises.
class EdbMappingRun {
  const EdbMappingRun({required this.calls, required this.auto, required this.queued, required this.none, required this.skipped});
  final int calls;
  final List<String> auto;
  final List<String> queued;
  final List<String> none;

  /// Not attempted because the call budget for the run ran out.
  final List<String> skipped;
}

/// Our exercise → ExerciseDB V2 id. Only IDs (permanent per AscendAPI) and the review queue are stored.
class EdbMappingRepository {
  EdbMappingRepository(this._db);
  final AppDatabase _db;

  static const assetPath = 'assets/edb_v2_map.json';

  Stream<List<EdbV2Map>> watchAll() => (_db.select(_db.edbV2Maps)..orderBy([(t) => OrderingTerm.asc(t.exerciseId)])).watch();

  Future<EdbV2Map?> get(String exerciseId) =>
      (_db.select(_db.edbV2Maps)..where((t) => t.exerciseId.equals(exerciseId))).getSingleOrNull();

  Future<void> _put(String exerciseId, {String? edbId, required String status, double confidence = 0, String query = '', List<EdbCandidate> candidates = const [], required DateTime now}) =>
      _db.into(_db.edbV2Maps).insertOnConflictUpdate(EdbV2MapsCompanion.insert(
            exerciseId: exerciseId,
            edbId: Value(edbId),
            status: status,
            confidence: Value(confidence),
            query: Value(query),
            candidates: Value(jsonEncode([for (final c in candidates.take(6)) c.toJson()])),
            updatedAt: now,
          ));

  /// One tap in the review screen.
  Future<void> confirm(String exerciseId, String edbId, {required DateTime now}) async {
    final cur = await get(exerciseId);
    await _put(exerciseId, edbId: edbId, status: 'confirmed', confidence: 1, query: cur?.query ?? '', now: now);
  }

  Future<void> markNone(String exerciseId, {required DateTime now}) => _put(exerciseId, status: 'none', now: now);

  /// Searches V2 for [info] (1 call) and, while [detailCalls] allows, fetches the top candidate to check
  /// its target muscles (1 call each). High confidence is accepted, the rest queued.
  Future<(EdbV2Map, int)> mapOne(ExerciseInfo info, EdbApi api, {required DateTime now, String? query, int detailCalls = 0}) async {
    final q = query ?? edbQueryFor(info);
    final hits = await api.search(q);
    var calls = 1;
    var ranked = scoreCandidates(info, [for (final h in hits) (id: h.exerciseId, name: h.name)]);
    if (!isConfident(ranked) && ranked.isNotEmpty && ranked.first.score >= 0.6 && detailCalls > 0) {
      final top = await api.exercise(ranked.first.edbId);
      calls++;
      ranked = [ranked.first.withMuscle(muscleAgreement(info, top.targetMuscles)), ...ranked.skip(1)]..sort((a, b) => b.score.compareTo(a.score));
    }
    final status = ranked.isEmpty ? 'none' : (isConfident(ranked) ? 'auto' : 'queued');
    await _put(
      info.id,
      edbId: status == 'auto' ? ranked.first.edbId : null,
      status: status,
      confidence: ranked.isEmpty ? 0 : ranked.first.score,
      query: q,
      candidates: status == 'auto' ? const [] : ranked,
      now: now,
    );
    return ((await get(info.id))!, calls);
  }

  /// Maps [infos] in order, never spending more than [maxCalls] API calls; already confirmed or auto
  /// mappings are left alone. Detail checks only use what the searches leave over.
  Future<EdbMappingRun> mapBatch(List<ExerciseInfo> infos, EdbApi api, {required DateTime now, int maxCalls = 150}) async {
    var calls = 0;
    final auto = <String>[], queued = <String>[], none = <String>[], skipped = <String>[];
    final todo = <ExerciseInfo>[];
    for (final i in infos) {
      final cur = await get(i.id);
      if (cur != null && (cur.status == 'confirmed' || cur.status == 'auto')) continue;
      todo.add(i);
    }
    for (var k = 0; k < todo.length; k++) {
      final info = todo[k];
      final remainingSearches = todo.length - k;
      if (calls >= maxCalls) {
        skipped.add(info.id);
        continue;
      }
      final spare = maxCalls - calls - remainingSearches;
      final (row, used) = await mapOne(info, api, now: now, detailCalls: spare > 0 ? 1 : 0);
      calls += used;
      switch (row.status) {
        case 'auto':
          auto.add(info.id);
        case 'queued':
          queued.add(info.id);
        default:
          none.add(info.id);
      }
    }
    return EdbMappingRun(calls: calls, auto: auto, queued: queued, none: none, skipped: skipped);
  }

  /// assets/edb_v2_map.json → rows that aren't in the DB yet (fresh install keeps the mappings).
  Future<int> seedFromAsset(String json, {required DateTime now}) async {
    final j = jsonDecode(json) as Map<String, dynamic>;
    var n = 0;
    for (final e in (j['mappings'] as Map<String, dynamic>).entries) {
      if (await get(e.key) != null) continue;
      final v = e.value as Map<String, dynamic>;
      await _db.into(_db.edbV2Maps).insert(EdbV2MapsCompanion.insert(
            exerciseId: e.key,
            edbId: Value(v['edbId'] as String?),
            status: v['status'] as String,
            confidence: Value((v['confidence'] as num?)?.toDouble() ?? 0),
            query: Value(v['query'] as String? ?? ''),
            candidates: Value(jsonEncode(v['candidates'] ?? const [])),
            updatedAt: now,
          ));
      n++;
    }
    return n;
  }

  /// Everything mapped so far, in the asset's format (paste into assets/edb_v2_map.json).
  Future<String> exportJson() async {
    final rows = await (_db.select(_db.edbV2Maps)..orderBy([(t) => OrderingTerm.asc(t.exerciseId)])).get();
    final body = const JsonEncoder.withIndent(' ').convert({
      'schema_version': 1,
      'description': 'Our exercise id -> ExerciseDB V2 exerciseId (stable IDs only; media URLs and text are never stored). '
          'status: auto | confirmed | queued | none. Queued rows keep their top candidates for review in Settings -> Debug -> Media matching.',
      'mappings': {
        for (final r in rows)
          r.exerciseId: {
            'edbId': r.edbId,
            'status': r.status,
            'confidence': double.parse(r.confidence.toStringAsFixed(3)),
            'query': r.query,
            if (r.status == 'queued') 'candidates': jsonDecode(r.candidates),
          },
      },
    });
    return '$body\n';
  }
}
