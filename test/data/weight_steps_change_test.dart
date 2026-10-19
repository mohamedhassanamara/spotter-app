import 'dart:math' as math;

import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/domain/history.dart';
import 'package:spotter/core/domain/load_types.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/workout/data/session_repository.dart';

const id = 'm';

GymEquipment gym({double start = 5, double step = 5, double? max, bool typed = true}) => GymEquipment(
      perExercise: typed ? {id: StackSpec(start: start, step: step)} : const {},
      typeOverrides: typed ? {id: LoadType.stack} : const {},
      maxLoads: max == null ? const {} : {id: max},
    );

WeightGrid gridOf(GymEquipment g, {Iterable<double> logged = const []}) => g.gridFor(exerciseId: id, type: LoadType.stack, logged: logged);

ExerciseInfo info() => ExerciseInfo(
      id: id,
      name: 'Machine Press',
      primaryMuscles: const ['chest'],
      secondaryMuscles: const [],
      equipment: 'machine',
      level: null,
      mechanic: 'compound',
      category: null,
      instructions: const [],
      images: const [],
      isCustom: false,
      isFavorite: false,
      notes: null,
    );

ExerciseSessionLog log(List<(double, int)> sets, {int day = 1}) => ExerciseSessionLog(
      sessionId: day,
      date: DateTime(2026, 10, day),
      suggestionKind: SuggestionKind.none,
      sets: [for (final s in sets) LoggedSet(weight: s.$1, reps: s.$2, rpe: 8)],
    );

CoachContext coachFor(GymEquipment g, List<ExerciseSessionLog> logs) => CoachContext(
      history: TrainingHistory.empty,
      readiness: null,
      overloaded: const {},
      freezes: const {},
      increments: Increments.defaults,
      now: DateTime(2026, 10, 14, 9),
      gym: g,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the grid', () {
    test('a changed starting weight shifts it: start 7 kg, step 5 kg → 7, 12, 17…', () {
      final g = gridOf(gym(start: 7, step: 5));
      expect(g.values.take(4), [7, 12, 17, 22]);
      expect(g.snap(60), 62);
    });

    test('weights logged under the old setting do not keep the old grid alive once you set the steps yourself', () {
      const logged = <double>[5, 10, 15, 60, 65];
      expect(gridOf(gym(start: 7, step: 5), logged: logged).values.take(3), [7, 12, 17], reason: 'an explicit setting is the truth');
      expect(gridOf(gym(start: 7, step: 5), logged: logged).contains(60), isFalse);
      // Without an explicit setting the logged weights still count (the default guess may be wrong).
      expect(gridOf(gym(typed: false), logged: [7.5]).contains(7.5), isTrue);
    });

    test('the max load caps the grid, including weights you logged above it', () {
      final g = gridOf(gym(max: 50), logged: [55, 60]);
      expect(g.values.last, 50);
      expect(g.maxLoad, 50);
    });
  });

  group('the suggestion follows the setting (outside a workout: it is computed fresh from the gym every time)', () {
    test('changing the step changes the suggested weight', () {
      final a = const SuggestionEngine().suggest(_input(gridOf(gym(step: 5)), [log([(60, 8), (60, 8), (60, 8)])]));
      final b = const SuggestionEngine().suggest(_input(gridOf(gym(step: 2.5)), [log([(60, 8), (60, 8), (60, 8)])]));
      expect(a.weight, 65, reason: 'next plate of a 5 kg stack');
      expect(b.weight, 62.5, reason: 'next plate once the step is 2.5 kg');
    });

    test('changing the starting weight moves the suggestion onto the new grid', () {
      final s = const SuggestionEngine().suggest(_input(gridOf(gym(start: 7, step: 5)), [log([(60, 8), (60, 8), (60, 8)])]));
      expect(gridOf(gym(start: 7, step: 5)).contains(s.weight), isTrue, reason: '${s.weight} is on 7, 12, 17…');
    });

    test('property: whatever the history, step, start and max, a suggestion is on the grid and never above the max', () {
      final rnd = math.Random(8);
      for (var n = 0; n < 4000; n++) {
        final start = [2.5, 5, 7, 10][rnd.nextInt(4)].toDouble();
        final step = [1.0, 2.5, 5.0, 7.0][rnd.nextInt(4)];
        final max = rnd.nextBool() ? null : 20 + rnd.nextInt(80).toDouble();
        final g = gym(start: start, step: step, max: max);
        final grid = gridOf(g, logged: [for (var i = 0; i < 3; i++) 10.0 + rnd.nextInt(120)]);
        final logs = [
          for (var d = 1; d <= 1 + rnd.nextInt(4); d++)
            log([for (var s = 0; s < 3; s++) (grid.values[rnd.nextInt(grid.values.length)], 4 + rnd.nextInt(10))], day: d),
        ];
        final s = const SuggestionEngine().suggest(_input(grid, logs, range: rnd.nextBool() ? const RepRange(6, 8) : const RepRange(10, 15)));
        final w = s.weight;
        if (s.rampUp) continue;
        expect(grid.contains(w), isTrue, reason: 'start $start step $step max $max: $w is off the grid');
        if (max != null) expect(w, lessThanOrEqualTo(max + 1e-6), reason: 'start $start step $step max $max: $w is above the max');
      }
    });
  });

  group('during a workout: the not-yet-completed sets re-snap, completed ones do not', () {
    late AppDatabase db;
    late SessionRepository repo;
    late int sessionId, exId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = SessionRepository(db);
      sessionId = await db.into(db.sessions).insert(SessionsCompanion.insert(name: 'T', startedAt: DateTime(2026, 10, 14, 9), status: const Value('active')));
      await db.into(db.exercises).insert(ExercisesCompanion.insert(id: id, name: 'Machine Press'));
      exId = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
          sessionId: sessionId, exerciseId: id, position: 0, repMin: 6, repMax: 8, targetSets: 4, restSeconds: 90, suggestedWeight: const Value(60)));
      for (var i = 0; i < 4; i++) {
        await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
            sessionExerciseId: exId,
            position: i,
            weight: const Value(60),
            reps: const Value(8),
            suggestedWeight: const Value(60),
            suggestedReps: const Value(8),
            targetRepMin: const Value(6),
            targetRepMax: const Value(8)));
      }
    });
    tearDown(() => db.close());

    Future<List<WorkoutSet>> sets() => (db.select(db.workoutSets)..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    Future<ActiveExercise> active() async => (await repo.loadActive())!.exercises.single;

    test('max load mid-workout: the remaining sets cap at once, the completed set stays as logged, the change is marked with its reason', () async {
      final first = (await sets()).first;
      await repo.completeSet(first, weight: 60, reps: 8, rpe: 8, isWarmup: false, now: DateTime(2026, 10, 14, 9, 5));
      final changed = await repo.applyEquipmentChange(await active(), grid: gridOf(gym(max: 50)), newSuggested: 50);
      expect(changed, 3);
      final all = await sets();
      expect(all[0].weight, 60, reason: 'completed: untouched');
      expect(all[0].completed, isTrue);
      expect(all[0].adjustReason, isNull);
      for (final s in all.skip(1)) {
        expect(s.weight, 50);
        expect(s.suggestedWeight, 50);
        expect(s.adjustedFrom, 60);
        expect(s.adjustReason, startsWith('Weight steps updated'));
        expect(s.adjustReason, contains('max load is 50'));
      }
      expect((await active()).row.suggestedWeight, 50);
    });

    test('starting weight / step mid-workout: untouched sets take the new suggestion, a weight you typed is only snapped', () async {
      final all = await sets();
      await (db.update(db.workoutSets)..where((t) => t.id.equals(all[2].id))).write(const WorkoutSetsCompanion(weight: Value(61)));
      await repo.applyEquipmentChange(await active(), grid: gridOf(gym(start: 7, step: 5)), newSuggested: 62);
      final after = await sets();
      expect(after[0].weight, 62, reason: '60 is not on 7, 12, … 62: the new suggestion');
      expect(after[1].weight, 62);
      expect(after[2].weight, 62, reason: 'typed 61 snaps to the nearest load');
      expect(after.every((s) => gridOf(gym(start: 7, step: 5)).contains(s.weight)), isTrue);
    });

    test('nothing to do when every set is already on the new grid', () async {
      expect(await repo.applyEquipmentChange(await active(), grid: gridOf(gym(step: 5)), newSuggested: 60), 0);
      expect((await sets()).every((s) => s.adjustReason == null), isTrue);
    });
  });
}

SuggestionInput _input(WeightGrid grid, List<ExerciseSessionLog> history, {RepRange range = const RepRange(6, 8)}) => SuggestionInput(
      range: range,
      targetSets: 3,
      targetRir: 2,
      increment: 5,
      equipment: EquipmentKind.machineCable,
      history: history,
      readiness: ExerciseReadiness.neutral,
      now: DateTime(2026, 10, 14),
      grid: grid,
    );
