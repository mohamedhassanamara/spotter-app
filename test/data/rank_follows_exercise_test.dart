import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/app_providers.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/history.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/ranks/data/rank_exclusions.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';
import 'package:spotter/features/workout/data/session_repository.dart';

/// Ranks follow the exercise id: added, never-done and swapped exercises rank at once, from the database (in-memory).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ProviderContainer c;
  late Map<String, ExerciseInfo> catalog;
  late SessionRepository sessions;
  late CoachContext coach;
  late String newId, otherId; // exercises without a hand-made standard, never done
  final now = DateTime(2026, 10, 12, 18);

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final repo = ExerciseRepository(db);
    await repo.ensureSeeded(jsonOverride: File('assets/exercises.json').readAsStringSync());
    catalog = await repo.watchCatalog().first;
    sessions = SessionRepository(db);
    coach = CoachContext(history: TrainingHistory.empty, readiness: null, overloaded: const {}, freezes: const {}, increments: Increments.defaults, now: now);
    final explicit = {for (final s in await RanksRepository.loadStandards()) ...s.exerciseIds};
    final free = [for (final e in catalog.values) if (!explicit.contains(e.id) && e.category == 'strength' && e.equipment == 'barbell') e.id];
    newId = free[0];
    otherId = free[1];
    await db.into(db.bodyWeights).insert(BodyWeightsCompanion.insert(measuredAt: now.subtract(const Duration(days: 1)), kg: 80, source: 'manual'));
    c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db), clockProvider.overrideWithValue(() => now)]);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
  });

  Future<int> startSession() => sessions.start(name: 'Test', coach: coach, catalog: catalog);

  Future<int> add(int sid, String id) => sessions.addExercise(
      sessionId: sid, info: catalog[id]!, range: const RepRange(6, 10), targetSets: 2, restSeconds: 120, targetRir: 2, coach: coach);

  Future<List<WorkoutSet>> setsOf(int exRowId) => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(exRowId))).get();

  Future<void> complete(WorkoutSet s, {double weight = 60, int reps = 8}) =>
      sessions.completeSet(s, weight: weight, reps: reps, rpe: 8, isWarmup: false, now: now);

  Future<void> listen(String id) async {
    c.listen(exerciseRankStateProvider(id), (_, _) {});
    c.listen(ranksProvider, (_, _) {});
    await settle();
  }

  test('every library exercise has a standard (hand-made or estimated)', () async {
    c.listen(catalogProvider, (_, _) {});
    c.listen(settingsProvider, (_, _) {});
    await settle();
    final standards = await c.read(standardsProvider.future);
    final byId = {for (final s in standards) for (final id in s.exerciseIds) id: s};
    for (final e in catalog.values) {
      expect(byId[e.id], isNotNull, reason: '${e.name} has no standard');
    }
    expect(byId[newId]!.estimated, isTrue);
  });

  test('adding a never-done exercise shows its rank state at once: not hidden, a standard, Unranked, Bronze 1 target', () async {
    final sid = await startSession();
    await add(sid, newId);
    await listen(newId);
    final st = c.read(exerciseRankStateProvider(newId));
    expect(st.hidden, isFalse, reason: 'an exercise of the running workout counts without any manual step');
    expect(st.standard, isNotNull);
    expect(st.estimated, isTrue);
    expect(st.score, isNull, reason: 'never done: unranked');
    expect(st.nextLabel, 'Bronze 1');
    expect(st.nextE1rm, greaterThan(0));
    expect((await RankExclusions(db).load()).contains(newId), isFalse);
  });

  test('the first completed set creates the rank; it updates live, unchecking removes it, warm-ups and zero-rep sets do not count', () async {
    final sid = await startSession();
    final row = await add(sid, newId);
    await listen(newId);
    final sets = await setsOf(row);
    final working = sets.where((s) => !s.isWarmup).toList();

    // A warm-up and a failed (0 reps) set do not rank.
    await sessions.completeSet(working[0], weight: 20, reps: 10, rpe: 8, isWarmup: true, now: now);
    await settle();
    expect(c.read(exerciseRankStateProvider(newId)).score, isNull, reason: 'warm-ups are excluded');

    await complete(working[1], weight: 40, reps: 8);
    await settle();
    final first = c.read(exerciseRankStateProvider(newId)).score;
    expect(first, isNotNull, reason: 'the first valid set creates the rank');

    // A heavier set raises it; unchecking it brings it back.
    await complete(working[0], weight: 90, reps: 8);
    await settle();
    final raised = c.read(exerciseRankStateProvider(newId)).score!;
    expect(raised.value, greaterThan(first!.value));
    await sessions.uncompleteSet(working[0].id);
    await settle();
    expect(c.read(exerciseRankStateProvider(newId)).score!.value, closeTo(first.value, 1e-9));
  });

  test('Finish persists the rank, and the muscle ranking includes the new exercise', () async {
    final sid = await startSession();
    final row = await add(sid, newId);
    await listen(newId);
    final s = (await setsOf(row)).where((x) => !x.isWarmup).first;
    await complete(s, weight: 60, reps: 8);
    await settle();
    final live = c.read(exerciseRankStateProvider(newId)).score!;
    await c.read(finishServiceProvider).finish(
        sessionId: sid, now: now, catalog: catalog, settings: c.read(currentSettingsProvider));
    c.invalidate(historyProvider);
    await c.read(ranksProvider.future);
    await settle();
    final summary = await c.read(ranksProvider.future);
    final r = summary.exercises.where((e) => e.exerciseId == newId).firstOrNull;
    expect(r, isNotNull, reason: 'persisted in the ranking after Finish');
    expect(r!.score.value, closeTo(live.value, 1e-6));
    expect(c.read(exerciseRankStateProvider(newId)).hidden, isFalse);
    expect(summary.muscles.values.any((m) => m.contributions.any((x) => x.rank.exerciseId == newId)), isTrue, reason: 'muscle ranking follows');
  });

  test('swap: logged sets stay with the original; the new exercise rebinds rank, PREV source and step', () async {
    final sid = await startSession();
    final row = await add(sid, newId);
    await listen(newId);
    await listen(otherId);
    final s = (await setsOf(row)).where((x) => !x.isWarmup).first;
    await complete(s, weight: 60, reps: 8);
    await settle();
    final active = (await sessions.loadActive())!;
    final newRow = await sessions.replaceExercise(old: active.exercises.first, info: catalog[otherId]!, coach: coach);
    await settle();

    final after = (await sessions.loadActive())!;
    expect(after.exercises.map((e) => e.row.exerciseId), [newId, otherId], reason: 'the original stays, the new one follows');
    expect((await setsOf(row)).where((x) => x.completed).length, 1, reason: 'logged sets stay on the original');
    expect((await setsOf(newRow)).where((x) => x.completed), isEmpty);
    expect(c.read(exerciseRankStateProvider(newId)).score, isNotNull);
    final other = c.read(exerciseRankStateProvider(otherId));
    expect(other.score, isNull, reason: 'the new exercise ranks on its own');
    expect(other.hidden, isFalse);
    expect(other.nextLabel, 'Bronze 1');
    expect(c.read(exerciseStepProvider(otherId)), 2.5);
  });

  test('swap with "move logged sets": they go to the new exercise and rank there, not on the original', () async {
    final sid = await startSession();
    final row = await add(sid, newId);
    await listen(newId);
    await listen(otherId);
    final s = (await setsOf(row)).where((x) => !x.isWarmup).first;
    await complete(s, weight: 60, reps: 8);
    final active = (await sessions.loadActive())!;
    final newRow = await sessions.replaceExercise(old: active.exercises.first, info: catalog[otherId]!, coach: coach, moveLoggedSets: true);
    await settle();
    final after = (await sessions.loadActive())!;
    expect(after.exercises.map((e) => e.row.exerciseId), [otherId]);
    expect((await setsOf(newRow)).where((x) => x.completed).length, 1);
    expect(c.read(exerciseRankStateProvider(otherId)).score, isNotNull);
    expect(c.read(exerciseRankStateProvider(newId)).score, isNull);
  });

  test('switched off by hand stays off', () async {
    final sid = await startSession();
    await add(sid, newId);
    await RankExclusions(db).set(newId, excluded: true);
    await listen(newId);
    expect(c.read(exerciseRankStateProvider(newId)).hidden, isTrue);
  });

  test('a custom exercise with a chosen movement pattern gets that pattern\'s standard', () async {
    final id = await ExerciseRepository(db).createCustom(
        name: 'My press', primaryMuscles: ['triceps'], secondaryMuscles: [], equipment: 'barbell', compound: true);
    await SettingsController(db).setExercisePattern(id, 'verticalPush');
    c.listen(settingsProvider, (_, _) {});
    c.listen(catalogProvider, (_, _) {});
    await settle();
    final standards = await c.read(standardsProvider.future);
    final std = standards.firstWhere((s) => s.exerciseIds.contains(id));
    expect(std.estimated, isTrue);
    expect(std.name, 'My press');
    // vertical-push compound barbell: base ohp × 0.9: beginner anchor 0.38 × 0.9
    expect(std.anchors.first, closeTo(0.38 * 0.9, 1e-3));
  });
}
