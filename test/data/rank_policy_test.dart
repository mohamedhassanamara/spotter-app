import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/ranks/data/rank_exclusions.dart';
import 'package:spotter/features/workout/data/session_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late String inRoutine, outside;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await bootstrapDatabase(db);
    final routineIds = {for (final r in await db.select(db.routineExercises).get()) r.exerciseId};
    inRoutine = routineIds.first;
    outside = (await db.select(db.exercises).get()).map((e) => e.id).firstWhere((id) => !routineIds.contains(id));
  });
  tearDown(() => db.close());

  Future<bool> counts(String id) async => !(await RankExclusions(db).load()).contains(id);

  /// A set of [exerciseId] in an in-app workout, completed through the same call ✓ makes.
  Future<void> complete(String exerciseId, {int reps = 8, bool warmup = false, String? type}) async {
    final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(name: 'T', startedAt: DateTime(2026, 10, 13, 9)));
    final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
        sessionId: sid, exerciseId: exerciseId, position: 0, repMin: 6, repMax: 8, targetSets: 2, restSeconds: 90));
    final id = await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
        sessionExerciseId: ex, position: 0, weight: const Value(40), reps: Value(reps), isWarmup: Value(warmup), setType: Value(type)));
    final set = await (db.select(db.workoutSets)..where((t) => t.id.equals(id))).getSingle();
    await SessionRepository(db).completeSet(set, weight: 40, reps: reps, rpe: 9, isWarmup: warmup, now: DateTime(2026, 10, 13, 9, 5));
  }

  test('default: only exercises in a current routine count; every other exercise is off', () async {
    expect(await counts(inRoutine), isTrue);
    expect(await counts(outside), isFalse);
    final excluded = await RankExclusions(db).load();
    final routineIds = {for (final r in await db.select(db.routineExercises).get()) r.exerciseId};
    expect(excluded.intersection(routineIds), isEmpty);
    expect(excluded.length, greaterThan(100));
  });

  test('a completed working set of a switched-off exercise switches it on (automatic)', () async {
    await complete(outside);
    expect(await counts(outside), isTrue);
    expect((await RankExclusions(db).policy()).sourceOf(outside), RankSource.auto);
  });

  test('no auto-enable from a warm-up, a drop set or an empty set', () async {
    await complete(outside, warmup: true);
    await complete(outside, type: 'drop');
    await complete(outside, reps: 0);
    expect(await counts(outside), isFalse);
  });

  test('imported history never switches anything on', () async {
    final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(
        name: 'Liftoff', startedAt: DateTime(2026, 5, 1), source: const Value('liftoff'), status: const Value('finished')));
    final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
        sessionId: sid, exerciseId: outside, position: 0, repMin: 6, repMax: 8, targetSets: 1, restSeconds: 90));
    await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
        sessionExerciseId: ex, position: 0, weight: const Value(50), reps: const Value(8), completed: const Value(true)));
    expect(await counts(outside), isFalse);
    // …and the one-time migration over existing data treats app sessions only.
    await db.deleteSetting(RankExclusions.migratedKey);
    await RankExclusions.ensureMigrated(db);
    expect(await counts(outside), isFalse);
  });

  test('a routine exercise switched off by hand stays off, even after a completed set', () async {
    await RankExclusions(db).set(inRoutine, excluded: true);
    expect(await counts(inRoutine), isFalse);
    await complete(inRoutine);
    expect(await counts(inRoutine), isFalse, reason: 'auto-enable never overrides a manual off');
    expect((await RankExclusions(db).policy()).sourceOf(inRoutine), RankSource.manualOff);
  });

  test('an exercise switched on by hand stays on', () async {
    await RankExclusions(db).set(outside, excluded: false);
    expect(await counts(outside), isTrue);
    expect((await RankExclusions(db).policy()).sourceOf(outside), RankSource.manualOn);
  });

  test('adding an exercise to a routine switches it on', () async {
    final routine = (await db.select(db.routines).get()).first;
    await db.into(db.routineExercises).insert(RoutineExercisesCompanion.insert(
        routineId: routine.id, exerciseId: outside, position: 99, repMin: 8, repMax: 12, targetSets: 3, restSeconds: 90));
    expect(await counts(outside), isTrue);
    expect((await RankExclusions(db).policy()).sourceOf(outside), RankSource.routine);
  });

  test('migration: hidden routine exercises stay off by hand; exercises done in-app switch on', () async {
    await db.deleteSetting(RankExclusions.migratedKey);
    await db.putSetting(RankExclusions.legacyKey, '["$inRoutine","$outside"]');
    final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(name: 'T', startedAt: DateTime(2026, 10, 1), status: const Value('finished')));
    final other = (await db.select(db.exercises).get()).map((e) => e.id).firstWhere((id) => id != outside && id != inRoutine);
    final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
        sessionId: sid, exerciseId: other, position: 0, repMin: 6, repMax: 8, targetSets: 1, restSeconds: 90));
    await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
        sessionExerciseId: ex, position: 0, weight: const Value(40), reps: const Value(8), completed: const Value(true)));
    await RankExclusions.ensureMigrated(db);
    final p = await RankExclusions(db).policy();
    expect(p.sourceOf(inRoutine), RankSource.manualOff);
    expect(p.sourceOf(outside), RankSource.off);
    expect(p.isOn(other), isTrue);
  });
}
