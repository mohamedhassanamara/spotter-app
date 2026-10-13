import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/db/database.dart';
import '../../../core/domain/training.dart';
import '../../../core/settings/app_settings.dart';
import '../../library/data/exercise_repository.dart';
import '../../library/domain/exercise_info.dart';
import '../domain/program.dart';

/// Legacy: the Monday of program week 1. Week tracking is gone; [ProgramRepository.ensureCanonicalWeek] deletes it.
const String programStartKey = 'program_start_monday';
const String routinesInstalledKey = 'program_routines_installed';

class ProgramRepository {
  ProgramRepository(this._db);
  final AppDatabase _db;

  static Program? _cache;

  static Future<Program> load() async =>
      _cache ??= Program.fromJson(jsonDecode(await rootBundle.loadString('assets/programs/min_max_canonical.json')) as Map<String, dynamic>);

  static Future<Map<String, dynamic>> loadMyRoutines() async =>
      jsonDecode(await rootBundle.loadString('assets/programs/my_routines.json')) as Map<String, dynamic>;

  /// Settings key recording that the canonical-week conversion ran (value: the canonical week).
  static const canonicalWeekKey = 'program_canonical_week';

  /// Startup step: converts state from the 12-week era to the one fixed week, once.
  /// - the program-start setting (week tracking) is deleted;
  /// - routine rows that follow the program take the canonical RIR of their first slot;
  /// - in a workout in progress, sets the program created automatically are cleaned up: pending drop,
  ///   myo and hold sets that carry a program technique are deleted, and pending working sets lose
  ///   their technique tag. Completed sets and everything in history are untouched.
  static Future<bool> ensureCanonicalWeek(AppDatabase db, {Program? program}) async {
    final p = program ?? await load();
    final week = '${p.canonicalWeek}';
    if (await db.getSetting(canonicalWeekKey) == week) return false;
    await db.transaction(() async {
      await db.deleteSetting(programStartKey);
      for (final r in await (db.select(db.routineExercises)..where((t) => t.programSlots.isNotNull())).get()) {
        final slot = p.slot(decodeSlots(r.programSlots).firstOrNull ?? '');
        final rir = slot?.rir.firstOrNull;
        if (rir != null && rir != r.targetRir) {
          await (db.update(db.routineExercises)..where((t) => t.id.equals(r.id))).write(RoutineExercisesCompanion(targetRir: Value(rir)));
        }
      }
      final active = await (db.select(db.sessions)..where((t) => t.status.equals('active'))).get();
      for (final session in active) {
        final exIds = [
          for (final e in await (db.select(db.sessionExercises)..where((t) => t.sessionId.equals(session.id))).get()) e.id,
        ];
        if (exIds.isEmpty) continue;
        await (db.delete(db.workoutSets)
              ..where((t) =>
                  t.sessionExerciseId.isIn(exIds) & t.completed.equals(false) & t.technique.isNotNull() & t.setType.isIn(['drop', 'myo', 'hold'])))
            .go();
        await (db.update(db.workoutSets)
              ..where((t) => t.sessionExerciseId.isIn(exIds) & t.completed.equals(false) & t.technique.isNotNull() & t.setType.isNull()))
            .write(const WorkoutSetsCompanion(technique: Value(null)));
        await (db.update(db.sessionExercises)..where((t) => t.id.isIn(exIds))).write(const SessionExercisesCompanion(programWeek: Value(null)));
      }
      await db.putSetting(canonicalWeekKey, week);
    });
    return true;
  }

  static const setCountsKey = 'routine_set_counts_restored';

  /// What [ensureRoutineSetCounts] restored, e.g. ["Upper · Dumbbell Incline Y Raise: 2 → 3"].
  static Future<List<String>> restoredSetCounts(AppDatabase db) async {
    final raw = await db.getSetting(setCountsKey);
    if (raw == null || raw.isEmpty || raw == '[]') return const [];
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  }

  /// Startup step, once: an earlier Red day removed a working set, and "Update routine" could save
  /// that lower count into the routine. Restores a program row to its count in `my_routines.json`
  /// when the evidence says so: the row has fewer sets than defined, and a finished session linked
  /// to it was a Red-day session (technique day) with exactly that many working sets. Your own set
  /// changes (no Red-day trace) are left alone.
  static Future<List<String>> ensureRoutineSetCounts(AppDatabase db, {Map<String, dynamic>? definition}) async {
    if (await db.getSetting(setCountsKey) != null) return const [];
    final def = definition ?? await loadMyRoutines();
    final fixed = <String>[];
    await db.transaction(() async {
      for (final routine in await db.select(db.routines).get()) {
        final defRoutine = (def['routines'] as List<dynamic>).cast<Map<String, dynamic>>().where((r) => r['name'] == routine.name).firstOrNull;
        if (defRoutine == null) continue;
        final rows = await (db.select(db.routineExercises)..where((t) => t.routineId.equals(routine.id))).get();
        for (final row in rows) {
          final slots = decodeSlots(row.programSlots);
          if (slots.isEmpty) continue;
          final defRow = (defRoutine['exercises'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .where((e) => (e['program_slots'] as List<dynamic>).cast<String>().join(',') == slots.join(','))
              .firstOrNull;
          final want = (defRow?['sets'] as num?)?.toInt();
          if (want == null || row.targetSets >= want) continue;
          final linked = await (db.select(db.sessionExercises).join([
            innerJoin(db.sessions, db.sessions.id.equalsExp(db.sessionExercises.sessionId)),
          ])
                ..where(db.sessionExercises.routineExerciseId.equals(row.id) & db.sessions.status.equals('finished')))
              .get();
          var redDay = false;
          for (final l in linked) {
            final e = l.readTable(db.sessionExercises);
            final technique = e.suggestionJson != null && (jsonDecode(e.suggestionJson!) as Map<String, dynamic>)['technique'] == true;
            if (!technique) continue;
            final working = await (db.select(db.workoutSets)
                  ..where((t) => t.sessionExerciseId.equals(e.id) & t.isWarmup.equals(false) & t.setType.isNull()))
                .get();
            if (working.length == row.targetSets) redDay = true;
          }
          if (!redDay) continue;
          await (db.update(db.routineExercises)..where((t) => t.id.equals(row.id))).write(RoutineExercisesCompanion(targetSets: Value(want)));
          fixed.add('${routine.name} · ${row.displayName ?? row.exerciseId}: ${row.targetSets} → $want');
        }
      }
      await db.putSetting(setCountsKey, jsonEncode(fixed));
    });
    return fixed;
  }

  static const supersetsKey = 'program_supersets_applied';

  /// Startup step, once: builds the program's supersets (S1/S2/S3 on Arms) into existing routines
  /// without reinstalling them. Rows are grouped by their first slot's label, in routine order, and
  /// take the program's rest rule (no rest on the first of a pair, the listed rest after the second).
  /// Other fields (your set counts, swaps, overrides) are left alone.
  static Future<bool> ensureProgramSupersets(AppDatabase db, {Program? program}) async {
    if (await db.getSetting(supersetsKey) == '1') return false;
    final p = program ?? await load();
    await db.transaction(() async {
      for (final routine in await db.select(db.routines).get()) {
        final rows = await (db.select(db.routineExercises)
              ..where((t) => t.routineId.equals(routine.id))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
        final groups = <String, int>{};
        for (final r in rows) {
          final slot = p.slot(decodeSlots(r.programSlots).firstOrNull ?? '');
          final label = slot?.superset;
          if (slot == null || label == null) continue;
          await (db.update(db.routineExercises)..where((t) => t.id.equals(r.id))).write(RoutineExercisesCompanion(
            supersetGroup: Value(groups[label] ??= r.id),
            restSeconds: Value(slot.rest?.maxSeconds ?? 0),
          ));
        }
      }
      await db.putSetting(supersetsKey, '1');
    });
    return true;
  }

  /// Startup step (before the UI exists, so Train never shows stale routines): installs the owner's
  /// routines on first launch, and reinstalls them when `my_routines.json` gets a newer version.
  static Future<bool> ensureMyRoutinesInstalled(AppDatabase db, {DateTime? now, Map<String, dynamic>? definition, Program? program}) async {
    final def = definition ?? await loadMyRoutines();
    final version = (def['schema_version'] as num?)?.toInt() ?? 1;
    final installed = int.tryParse(await db.getSetting(routinesInstalledKey) ?? '');
    if (installed != null && installed >= version) return false;
    final rows = await db.select(db.exercises).get();
    final catalog = {for (final r in rows) r.id: ExerciseRepository.toInfo(r)};
    final settings = SettingsModel.fromMap(await db.watchSettings().first);
    await ProgramRepository(db).installMyRoutines(
      program: program ?? await load(),
      definition: def,
      catalog: catalog,
      settings: settings,
      now: now ?? DateTime.now(),
    );
    return true;
  }

  /// Replaces all routines with the owner's program routines (sessions are kept; they don't
  /// reference routine rows). Rows missing from the catalogue are skipped and returned.
  Future<List<String>> installMyRoutines({
    required Program program,
    required Map<String, dynamic> definition,
    required Map<String, ExerciseInfo> catalog,
    required SettingsModel settings,
    required DateTime now,
  }) async {
    final skipped = <String>[];
    await _db.transaction(() async {
      await _db.delete(_db.routineExercises).go();
      await _db.delete(_db.routines).go();
      var rPos = 0;
      for (final r in (definition['routines'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final routineId = await _db.into(_db.routines).insert(RoutinesCompanion.insert(
              name: r['name'] as String,
              position: Value(rPos++),
              createdAt: now,
              programDay: Value(r['day'] as String),
            ));
        var pos = 0;
        final supersets = <String, int>{};
        for (final e in (r['exercises'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          final id = e['exercise_id'] as String;
          final slots = (e['program_slots'] as List<dynamic>).cast<String>();
          final first = program.slot(slots.first);
          if (catalog[id] == null || first == null) {
            skipped.add(e['name'] as String);
            continue;
          }
          final rowId = await _db.into(_db.routineExercises).insert(RoutineExercisesCompanion.insert(
                routineId: routineId,
                exerciseId: id,
                position: pos++,
                repMin: first.repRange.min,
                repMax: first.repRange.max,
                targetSets: (e['sets'] as num).toInt(),
                restSeconds: first.rest?.maxSeconds ?? 0,
                targetRir: Value(first.rir.firstOrNull ?? settings.defaultRir),
                programSlots: Value(jsonEncode(slots)),
                programRelation: Value(e['relation'] as String?),
                programExercise: Value(e['program_exercise'] as String?),
                displayName: Value(e['name'] as String?),
              ));
          // The program's S1/S2/S3 labels: rows sharing a label in a day are one superset.
          final label = first.superset;
          if (label != null) {
            await (_db.update(_db.routineExercises)..where((t) => t.id.equals(rowId)))
                .write(RoutineExercisesCompanion(supersetGroup: Value(supersets[label] ??= rowId)));
          }
        }
      }
      await _db.putSetting(routinesInstalledKey, '${definition['schema_version'] ?? 1}');
      // The program trains 5 days a week (two planned rest days).
      await _db.putSetting(SettingsModel.kWeeklyGoal, '${program.sessionsPerWeek}');
    });
    return skipped;
  }
}

/// Program slots stored on a routine or session row.
List<String> decodeSlots(String? raw) => raw == null ? const [] : (jsonDecode(raw) as List<dynamic>).cast<String>();

RepRange? rangeOf(int? min, int? max) => (min == null || max == null) ? null : RepRange(min, max);
