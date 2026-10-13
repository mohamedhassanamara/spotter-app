import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/history.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/workout/data/routine_repository.dart';
import 'package:spotter/features/workout/data/routine_sync.dart';
import 'package:spotter/features/workout/data/session_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime(2026, 10, 12, 18);
  final coach = CoachContext(
    history: TrainingHistory.empty,
    readiness: null,
    overloaded: const {},
    freezes: const {},
    increments: Increments.defaults,
    now: now,
  );

  late AppDatabase db;
  late Map<String, ExerciseInfo> catalog;
  late RoutineRepository routines;
  late SessionRepository sessions;
  late int routineId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ex = ExerciseRepository(db);
    await ex.ensureSeeded(
      jsonOverride: File('assets/exercises.json').readAsStringSync(),
      extraJsonOverride: File('assets/extra_exercises.json').readAsStringSync(),
      sourcesJsonOverride: File('assets/library_sources.json').readAsStringSync(),
    );
    catalog = await ex.watchCatalog().first;
    routines = RoutineRepository(db);
    sessions = SessionRepository(db);
    routineId = await routines.create('Push', now: now);
    for (final id in ['Barbell_Bench_Press_-_Medium_Grip', 'Barbell_Curl', 'Dumbbell_Flyes']) {
      await routines.addExercise(routineId, catalog[id]!, const SettingsModel());
    }
  });
  tearDown(() => db.close());

  Future<ActiveSession> startFromRoutine() async {
    final r = await routines.watchRoutine(routineId).first;
    await sessions.start(name: 'Push', coach: coach, catalog: catalog, routine: r);
    return (await sessions.watchActive().first)!;
  }

  test('an untouched session matches its routine', () async {
    final s = await startFromRoutine();
    final rows = await routineRows(db, routineId);
    expect(diffSessionAgainstRoutine(session: s.exercises, routine: rows, catalog: catalog).isEmpty, isTrue);
  });

  test('add, remove, reorder, extra set and target reps are detected and applied', () async {
    var s = await startFromRoutine();
    final bench = s.exercises[0], curl = s.exercises[1], fly = s.exercises[2];
    await sessions.removeExercise(curl.row.id);
    await sessions.reorderExercises([fly.row.id, bench.row.id]);
    await sessions.addSet(bench);
    await sessions.setTargetReps(fly, const RepRange(12, 15));
    await sessions.addExercise(
      sessionId: s.session.id,
      info: catalog['Triceps_Pushdown']!,
      range: const RepRange(10, 15),
      targetSets: 2,
      restSeconds: 90,
      targetRir: 1,
      coach: coach,
    );
    s = (await sessions.watchActive().first)!;
    final rows = await routineRows(db, routineId);
    final diff = diffSessionAgainstRoutine(session: s.exercises, routine: rows, catalog: catalog);
    expect(diff.removed, ['Barbell Curl']);
    expect(diff.added, hasLength(1));
    expect(diff.reordered, isTrue);
    expect(diff.setCounts.single, contains('3 → 4 sets'));
    expect(diff.targets.single, contains('12–15'));

    await updateRoutineFromSession(db: db, routineId: routineId, session: s.exercises, catalog: catalog);
    final after = await routineRows(db, routineId);
    expect(after.map((r) => r.exerciseId).take(2), ['Dumbbell_Flyes', 'Barbell_Bench_Press_-_Medium_Grip']);
    expect(after, hasLength(3));
    expect(after[1].targetSets, 4);
    expect((after[0].repMin, after[0].repMax, after[0].overrideRepMin), (12, 15, 12));

    // Once updated, the same session no longer differs.
    s = (await sessions.watchActive().first)!;
    final again = diffSessionAgainstRoutine(session: s.exercises, routine: after, catalog: catalog);
    expect(again.added, isEmpty);
    expect(again.removed, isEmpty);
  });

  test('sets readiness skipped today are not a routine change', () async {
    final s = await startFromRoutine();
    final bench = s.exercises.first;
    // As on a Red day: one working set fewer, recorded on the suggestion.
    final lastWorking = bench.sets.lastWhere((x) => !x.isWarmup);
    await sessions.deleteSet(lastWorking);
    await (db.update(db.sessionExercises)..where((t) => t.id.equals(bench.row.id)))
        .write(SessionExercisesCompanion(suggestionJson: Value(bench.row.suggestionJson!.replaceFirst('{', '{"trimmed":1,'))));
    final now2 = (await sessions.watchActive().first)!;
    final diff = diffSessionAgainstRoutine(session: now2.exercises, routine: await routineRows(db, routineId), catalog: catalog);
    expect(diff.setCounts, isEmpty);
    expect(now2.exercises.first.suggestion!.setsTrimmed, 1);
  });

  test('a replaced exercise keeps its routine row', () async {
    final s = await startFromRoutine();
    await sessions.replaceExercise(old: s.exercises[1], info: catalog['Hammer_Curls']!, coach: coach);
    final now2 = (await sessions.watchActive().first)!;
    final diff = diffSessionAgainstRoutine(session: now2.exercises, routine: await routineRows(db, routineId), catalog: catalog);
    expect(diff.replaced.single, startsWith('Barbell Curl → '));
    expect(diff.added, isEmpty);
    await updateRoutineFromSession(db: db, routineId: routineId, session: now2.exercises, catalog: catalog);
    final rows = await routineRows(db, routineId);
    expect(rows[1].exerciseId, 'Hammer_Curls');
  });
}
