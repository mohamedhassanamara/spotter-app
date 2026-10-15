import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/app_providers.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/history.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/domain/load_types.dart';
import 'package:spotter/features/workout/data/session_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late SessionRepository repo;
  late int exId;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SessionRepository(db);
    final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(name: 'T', startedAt: DateTime(2026, 10, 14, 9)));
    await db.into(db.exercises).insert(ExercisesCompanion.insert(id: 'm', name: 'Machine'));
    exId = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
        sessionId: sid, exerciseId: 'm', position: 0, repMin: 6, repMax: 8, targetSets: 3, restSeconds: 90));
    for (var i = 0; i < 3; i++) {
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
          sessionExerciseId: exId,
          position: i,
          weight: const Value(80),
          reps: const Value(8),
          suggestedWeight: const Value(80),
          suggestedReps: const Value(8),
          targetRepMin: const Value(6),
          targetRepMax: const Value(8)));
    }
  });
  tearDown(() => db.close());

  final grid = const GymEquipment(perExercise: {'m': StackSpec(start: 5, step: 5)}).gridFor(exerciseId: 'm', type: LoadType.stack);
  Future<List<WorkoutSet>> sets() => (db.select(db.workoutSets)..orderBy([(t) => OrderingTerm.asc(t.position)])).get();

  Future<WorkoutSet> complete(int index, {required int reps, double weight = 80}) async {
    final s = (await sets())[index];
    await repo.completeSet(s, weight: weight, reps: reps, rpe: 10, isWarmup: false, now: DateTime(2026, 10, 14, 9, 10));
    return (await sets())[index];
  }

  test('missed reps: only the later, untouched sets of the same exercise move one step lighter, with the reason', () async {
    final done = await complete(0, reps: 4);
    final changed = await repo.adaptLaterSets(done, grid: grid, exerciseRepMin: 6);
    expect(changed.length, 2);
    final all = await sets();
    expect(all[0].weight, 80, reason: 'the finished set is history');
    expect(all[1].weight, 75);
    expect(all[1].suggestedWeight, 75);
    expect(all[1].adjustedFrom, 80);
    expect(all[1].adjustReason, contains('Set 1: 4 reps at 80 kg, below the 6–8 rep range'));
    expect(all[2].weight, 75);
    expect(all[1].reps, 8, reason: 'the rep target is untouched');
  });

  test('in range, above range or a set you already edited: no change', () async {
    expect(await repo.adaptLaterSets(await complete(0, reps: 6), grid: grid, exerciseRepMin: 6), isEmpty);
    expect(await repo.adaptLaterSets(await complete(1, reps: 12), grid: grid, exerciseRepMin: 6), isEmpty);
    // The last set was typed over by hand: leave it.
    await repo.updateSet((await sets())[2].id, weight: 85);
    final done = await complete(0, reps: 3);
    expect(await repo.adaptLaterSets(done, grid: grid, exerciseRepMin: 6), isEmpty, reason: 'set 2 is done, set 3 was edited');
    expect((await sets())[2].weight, 85);
    expect((await sets())[2].adjustReason, isNull);
  });

  test('a second miss keeps the original planned weight and never raises one', () async {
    var done = await complete(0, reps: 4);
    await repo.adaptLaterSets(done, grid: grid, exerciseRepMin: 6);
    done = await complete(1, reps: 3, weight: 75);
    await repo.adaptLaterSets(done, grid: grid, exerciseRepMin: 6);
    final last = (await sets())[2];
    expect(last.weight, 70);
    expect(last.adjustedFrom, 80, reason: 'what the plan said at the start');
  });

  frozenContextTests();

  test('warm-ups, drops and the first step of the grid never adapt', () async {
    final s = (await sets())[0];
    await repo.completeSet(s, weight: 80, reps: 2, rpe: 10, isWarmup: true, now: DateTime(2026, 10, 14, 9));
    final warm = (await sets())[0];
    expect(await repo.adaptLaterSets(warm, grid: grid, exerciseRepMin: 6), isEmpty);
    final low = (await sets())[0].copyWith(weight: 5, reps: 1, isWarmup: false);
    expect(await repo.adaptLaterSets(low, grid: grid, exerciseRepMin: 6), isEmpty, reason: 'nothing lighter exists');
  });
}

void frozenContextTests() {
  test('mid-workout planning (swap, form reset, add) reuses the context the workout started with', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final started = CoachContext(history: TrainingHistory.empty, readiness: null, overloaded: const {}, freezes: const {}, increments: Increments.defaults, now: DateTime(2026, 10, 14, 9));
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    c.read(frozenCoachProvider.notifier).freeze(7, started);
    // A Health sync / readiness refresh in between changes nothing the workout sees.
    expect(identical(await c.read(workoutCoachProvider)(7), started), isTrue);
    expect(identical(await c.read(workoutCoachProvider)(7), started), isTrue);
    c.dispose();
    await db.close();
  });
}
