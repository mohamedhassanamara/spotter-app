import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/program/data/program_repository.dart';
import 'package:spotter/features/program/domain/program.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final program = Program.fromJson(jsonDecode(File('assets/programs/min_max_canonical.json').readAsStringSync()) as Map<String, dynamic>);
  final now = DateTime(2026, 10, 13, 9);

  test('12-week state → one fixed week: week setting gone, routine RIR canonical, auto technique sets cleaned, history kept', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await ExerciseRepository(db).ensureSeeded(
      jsonOverride: File('assets/exercises.json').readAsStringSync(),
      extraJsonOverride: File('assets/extra_exercises.json').readAsStringSync(),
      sourcesJsonOverride: File('assets/library_sources.json').readAsStringSync(),
    );
    // Old state: a program start date (week tracking) and a Hack Squat row with week-2 RIR 1.
    await db.putSetting(programStartKey, '2026-09-07');
    final rid = await db.into(db.routines).insert(RoutinesCompanion.insert(name: 'Lower', createdAt: now));
    final hack = await db.into(db.routineExercises).insert(RoutineExercisesCompanion.insert(
          routineId: rid,
          exerciseId: 'Hack_Squat',
          position: 0,
          repMin: 4,
          repMax: 6,
          targetSets: 2,
          restSeconds: 240,
          targetRir: const Value(1),
          programSlots: const Value('["lower_02"]'),
        ));
    // A finished week-8 session (history) and a workout in progress with auto-created drops.
    Future<int> session(String status) => db.into(db.sessions).insert(SessionsCompanion.insert(name: 'Lower', startedAt: now, status: Value(status)));
    final done = await session('finished');
    final live = await session('active');
    Future<int> ex(int sessionId) => db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
          sessionId: sessionId,
          exerciseId: 'Lying_Leg_Curls',
          position: 0,
          repMin: 8,
          repMax: 10,
          targetSets: 2,
          restSeconds: 90,
          programWeek: const Value(8),
        ));
    final doneEx = await ex(done), liveEx = await ex(live);
    Future<int> set(int exId, int pos, {String? type, String? technique, bool completed = false}) => db.into(db.workoutSets).insert(
        WorkoutSetsCompanion.insert(sessionExerciseId: exId, position: pos, setType: Value(type), technique: Value(technique), completed: Value(completed)));
    await set(doneEx, 0, technique: 'drop_sets_2x25', completed: true);
    await set(doneEx, 1, type: 'drop', technique: 'drop_sets_2x25', completed: true);
    final working = await set(liveEx, 0, technique: 'drop_sets_2x25');
    await set(liveEx, 1, type: 'drop', technique: 'drop_sets_2x25');
    await set(liveEx, 2, type: 'drop', technique: 'drop_sets_2x25');
    final manualDrop = await set(liveEx, 3, type: 'drop'); // added by hand: kept

    expect(await ProgramRepository.ensureCanonicalWeek(db, program: program), isTrue);

    expect(await db.getSetting(programStartKey), isNull);
    expect(await db.getSetting(ProgramRepository.canonicalWeekKey), '5');
    final row = await (db.select(db.routineExercises)..where((t) => t.id.equals(hack))).getSingle();
    expect(row.targetRir, 0, reason: 'Hack Squat week 5 = RIR 0/2');
    final liveSets = await (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(liveEx))).get();
    expect(liveSets.map((s) => s.id), [working, manualDrop]);
    expect(liveSets.first.technique, isNull);
    final doneSets = await (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(doneEx))).get();
    expect(doneSets, hasLength(2), reason: 'history untouched');
    expect(doneSets.first.technique, 'drop_sets_2x25');
    final liveRow = await (db.select(db.sessionExercises)..where((t) => t.id.equals(liveEx))).getSingle();
    expect(liveRow.programWeek, isNull);

    expect(await ProgramRepository.ensureCanonicalWeek(db, program: program), isFalse, reason: 'runs once');
    await db.close();
  });
}
