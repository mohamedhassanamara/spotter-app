import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/training.dart';
import '../../../core/providers.dart';
import '../domain/export_schema.dart';

final exportServiceProvider = Provider<ExportService>((ref) => ExportService(ref.watch(databaseProvider)));

/// Exports all on-device data as JSON or CSV (see docs/export_schema.md).
class ExportService {
  ExportService(this._db);
  final AppDatabase _db;

  Future<Map<String, String>> _exerciseNames() async =>
      {for (final e in await _db.select(_db.exercises).get()) e.id: e.name};

  Map<String, Object?> _setMap(WorkoutSet s) {
    final working = s.completed && !s.isWarmup;
    final e1rm = working ? estimateOneRm(s.weight, s.reps, s.rpe) : null;
    return {
      'set_id': s.id,
      'position': s.position,
      'is_warmup': s.isWarmup,
      'weight_kg': s.weight,
      'reps': s.reps,
      'rpe': s.rpe,
      'rir': s.rpe == null ? null : 10 - s.rpe!,
      'completed': s.completed,
      'completed_at': isoLocalOrNull(s.completedAt),
      'suggested_weight_kg': s.suggestedWeight,
      'suggested_reps': s.suggestedReps,
      'is_override': s.isOverride,
      'override_reason': s.overrideReason,
      'e1rm_kg': e1rm == null || e1rm == 0 ? null : double.parse(e1rm.toStringAsFixed(2)),
      'set_type': s.setType ?? (s.isWarmup ? 'warmup' : 'working'),
      'partials': s.partials,
      'rest_seconds': s.restSeconds,
      'is_ego_set': s.isOverride && s.targetRepMin != null && s.reps < s.targetRepMin!,
    };
  }

  Map<String, Object?> _sessionMap(Session s) => {
        'id': s.id,
        'name': s.name,
        'routine_id': s.routineId,
        'started_at': isoLocal(s.startedAt),
        'ended_at': isoLocalOrNull(s.endedAt),
        'duration_s': s.endedAt?.difference(s.startedAt).inSeconds,
        'notes': s.notes,
        'readiness_score': s.readinessScore,
        'readiness_band': s.readinessBand,
        'xp_earned': s.xpEarned,
        'health_synced': s.healthSynced,
      };

  Map<String, Object?> _readinessMap(DailyMetric d) => {
        'date': d.date,
        'hrv_ms': d.hrvMs,
        'resting_hr_bpm': d.restingHr,
        'sleep_minutes': d.sleepMinutes,
        'active_energy_kcal': d.activeEnergyKcal,
        'readiness_score': d.readinessScore,
        'readiness_band': d.readinessBand,
        'calibrating': d.calibrating,
        'explanation': d.explanation,
      };

  Future<List<Session>> _sessions() => (_db.select(_db.sessions)
        ..where((t) => t.status.equals('finished'))
        ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
      .get();

  Future<Map<int, List<SessionExercise>>> _exercisesBySession() async {
    final rows = await (_db.select(_db.sessionExercises)..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final out = <int, List<SessionExercise>>{};
    for (final r in rows) {
      (out[r.sessionId] ??= []).add(r);
    }
    return out;
  }

  Future<Map<int, List<WorkoutSet>>> _setsByExercise() async {
    final rows = await (_db.select(_db.workoutSets)..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final out = <int, List<WorkoutSet>>{};
    for (final r in rows) {
      (out[r.sessionExerciseId] ??= []).add(r);
    }
    return out;
  }

  Future<List<DailyMetric>> _days() =>
      (_db.select(_db.dailyMetrics)..orderBy([(t) => OrderingTerm.asc(t.date)])).get();

  /// The complete export document.
  Future<Map<String, Object?>> buildJson(DateTime now) async {
    final names = await _exerciseNames();
    final exBySession = await _exercisesBySession();
    final setsByEx = await _setsByExercise();
    final routines = await (_db.select(_db.routines)..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final routineEx = await (_db.select(_db.routineExercises)..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final bodyweights = await (_db.select(_db.bodyWeights)..orderBy([(t) => OrderingTerm.asc(t.measuredAt)])).get();
    final custom = await (_db.select(_db.exercises)..where((t) => t.isCustom.equals(true))).get();
    final freezes = await (_db.select(_db.egoFreezes)..orderBy([(t) => OrderingTerm.asc(t.startedAt)])).get();
    final xp = await (_db.select(_db.xpEvents)..orderBy([(t) => OrderingTerm.asc(t.at)])).get();
    final achievements = await _db.select(_db.achievementsUnlocked).get();

    return {
      'schema_version': exportSchemaVersion,
      'app': 'spotter',
      'exported_at': isoLocal(now),
      'units': {'weight': 'kg', 'sleep': 'minutes', 'energy': 'kcal', 'hrv': 'ms', 'heart_rate': 'bpm'},
      'bodyweights': [
        for (final b in bodyweights) {'id': b.id, 'measured_at': isoLocal(b.measuredAt), 'kg': b.kg, 'source': b.source},
      ],
      'routines': [
        for (final r in routines)
          {
            'id': r.id,
            'name': r.name,
            'position': r.position,
            'created_at': isoLocal(r.createdAt),
            'exercises': [
              for (final e in routineEx.where((e) => e.routineId == r.id))
                {
                  'exercise_id': e.exerciseId,
                  'exercise_name': names[e.exerciseId],
                  'position': e.position,
                  'rep_min': e.repMin,
                  'rep_max': e.repMax,
                  'target_sets': e.targetSets,
                  'target_rir': e.targetRir,
                  'rest_s': e.restSeconds,
                },
            ],
          },
      ],
      'sessions': [
        for (final s in await _sessions())
          {
            ..._sessionMap(s),
            'exercises': [
              for (final e in exBySession[s.id] ?? const <SessionExercise>[])
                {
                  'session_exercise_id': e.id,
                  'exercise_id': e.exerciseId,
                  'exercise_name': names[e.exerciseId] ?? e.exerciseId,
                  'position': e.position,
                  'rep_min': e.repMin,
                  'rep_max': e.repMax,
                  'target_sets': e.targetSets,
                  'target_rir': e.targetRir,
                  'rest_s': e.restSeconds,
                  'suggestion_kind': e.suggestionKind,
                  'suggested_weight': e.suggestedWeight,
                  'suggested_reps': e.suggestedReps,
                  'suggested_sets': e.suggestedSets,
                  'notes': e.notes,
                  'sets': [for (final w in setsByEx[e.id] ?? const <WorkoutSet>[]) _setMap(w)],
                },
            ],
          },
      ],
      'readiness_days': [for (final d in await _days()) _readinessMap(d)],
      'custom_exercises': [
        for (final c in custom)
          {
            'id': c.id,
            'name': c.name,
            'primary_muscles': jsonDecode(c.primaryMuscles),
            'secondary_muscles': jsonDecode(c.secondaryMuscles),
            'equipment': c.equipment,
            'mechanic': c.mechanic,
            'notes': c.notes,
          },
      ],
      'ego_freezes': [
        for (final f in freezes)
          {
            'id': f.id,
            'exercise_id': f.exerciseId,
            'started_at': isoLocal(f.startedAt),
            'until': isoLocal(f.until),
            'base_weight_kg': f.baseWeight,
            'reason': f.reason,
          },
      ],
      'xp_events': [
        for (final x in xp)
          {'id': x.id, 'at': isoLocal(x.at), 'amount': x.amount, 'reason': x.reason, 'session_id': x.sessionId, 'week_start': x.weekStart},
      ],
      'achievements': [
        for (final a in achievements) {'key': a.key, 'unlocked_at': isoLocal(a.unlockedAt)},
      ],
    };
  }

  Future<File> writeJson(Directory dir, DateTime now) async {
    final doc = await buildJson(now);
    final file = File(p.join(dir.path, 'spotter-export-${fileStamp(now)}.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(doc));
    return file;
  }

  Future<List<File>> writeCsv(Directory dir, DateTime now) async {
    final names = await _exerciseNames();
    final sessions = await _sessions();
    final exBySession = await _exercisesBySession();
    final setsByEx = await _setsByExercise();
    final stamp = fileStamp(now);

    final setRows = <Map<String, Object?>>[];
    for (final s in sessions) {
      for (final e in exBySession[s.id] ?? const <SessionExercise>[]) {
        for (final w in setsByEx[e.id] ?? const <WorkoutSet>[]) {
          setRows.add({
            'session_id': s.id,
            'session_started_at': isoLocal(s.startedAt),
            'session_exercise_id': e.id,
            'exercise_id': e.exerciseId,
            'exercise_name': names[e.exerciseId] ?? e.exerciseId,
            'exercise_position': e.position,
            'rep_min': e.repMin,
            'rep_max': e.repMax,
            'target_rir': e.targetRir,
            'suggestion_kind': e.suggestionKind,
            ..._setMap(w),
          });
        }
      }
    }

    Future<File> write(String name, String content) async {
      final f = File(p.join(dir.path, 'spotter-$name-$stamp.csv'));
      await f.writeAsString(content);
      return f;
    }

    return [
      await write('sessions', toCsv(sessionCsvColumns, sessions.map(_sessionMap))),
      await write('sets', toCsv(setCsvColumns, setRows)),
      await write('readiness-days', toCsv(readinessCsvColumns, (await _days()).map(_readinessMap))),
    ];
  }

  /// Writes the export to a temp folder and opens the iOS share sheet.
  Future<void> share({required bool csv, Rect? origin}) async {
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final files = csv ? await writeCsv(dir, now) : [await writeJson(dir, now)];
    await SharePlus.instance.share(ShareParams(
      files: [for (final f in files) XFile(f.path)],
      subject: 'Spotter export ${fileStamp(now)}',
      sharePositionOrigin: origin,
    ));
  }
}
