import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/readiness/data/readiness_repository.dart' show BodyWeightRepository;
import 'package:spotter/features/library/data/exercise_merger.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';
import 'package:spotter/features/workout/data/history_repository.dart';
import 'package:spotter/features/workout/data/routine_repository.dart';
import 'package:spotter/features/ranks/data/rank_exclusions.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const dup = 'edbv1_oHsrypV', canon = 'Thigh_Adductor';
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await bootstrapDatabase(db);
  });
  tearDown(() => db.close());

  Future<int> session(String exerciseId, {required String source, String? displayName, required DateTime at, double kg = 40, int reps = 12}) async {
    final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(
        name: 'W', startedAt: at, source: Value(source), status: const Value('finished'), endedAt: Value(at.add(const Duration(hours: 1)))));
    final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
        sessionId: sid, exerciseId: exerciseId, position: 0, repMin: 8, repMax: 12, targetSets: 1, restSeconds: 90, displayName: Value(displayName)));
    await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
        sessionExerciseId: ex, position: 0, weight: Value(kg), reps: Value(reps), rpe: const Value(9), completed: const Value(true), completedAt: Value(at)));
    return ex;
  }

  /// bootstrap already merged the duplicate away; put it back like a library re-seed would.
  Future<void> restoreDuplicate() async {
    final row = (await db.select(db.exercises).get()).firstWhere((e) => e.id == canon);
    await db.into(db.exercises).insert(ExercisesCompanion.insert(
        id: dup, name: 'Machine Seated Hip Adduction', equipment: Value(row.equipment), extraImages: Value(jsonEncode(['https://x/y.gif'])), isFavorite: const Value(true)));
  }

  test('a fresh install has no duplicate entries and the canonical has the name the app logs', () async {
    final ids = {for (final e in await db.select(db.exercises).get()) e.id: e.name};
    for (final m in await ExerciseMerger.loadAsset()) {
      if (!ids.containsKey(m.canonical)) continue; // an import custom that doesn't exist yet
      expect(ids.containsKey(m.duplicate), isFalse, reason: '${m.duplicate} should be merged away');
    }
    expect(ids[canon], 'Machine Seated Hip Adduction');
    expect(ids['Thigh_Abductor'], 'Machine Seated Hip Abduction');
  });

  test('the hip adduction case: Liftoff history and the in-app workout end up on one exercise, ranked and counted', () async {
    await restoreDuplicate();
    await session(canon, source: 'liftoff', displayName: 'Hip Adduction', at: DateTime(2026, 9, 20), kg: 45);
    await session(dup, source: 'app', at: DateTime(2026, 10, 13), kg: 50);
    await RankExclusions(db).autoEnable(dup); // the in-app set switched the duplicate on
    await (db.update(db.exercises)..where((t) => t.id.equals(canon))).write(const ExercisesCompanion(isFavorite: Value(false)));

    final results = await ExerciseMerger(db).apply();
    final r = results.singleWhere((x) => x.merge.duplicate == dup);
    expect(r.historyRows, 1);

    expect((await db.select(db.exercises).get()).any((e) => e.id == dup), isFalse);
    final rows = await db.select(db.sessionExercises).get();
    expect(rows.where((e) => e.exerciseId == canon), hasLength(2), reason: 'both sessions are on the canonical id');
    expect(rows.firstWhere((e) => e.displayName == 'Machine Seated Hip Adduction').exerciseId, canon, reason: 'the logged name is kept');
    final canonical = await (db.select(db.exercises)..where((t) => t.id.equals(canon))).getSingle();
    expect(canonical.isFavorite, isTrue, reason: 'favourite carried over');
    expect(jsonDecode(canonical.extraImages), contains('https://x/y.gif'), reason: 'media carried over');
    final p = await RankExclusions(db).policy();
    expect(p.isOn(canon), isTrue, reason: 'the auto-enable moved with it');
    expect((await RankExclusions(db).load()).contains(canon), isFalse);
    expect((await ExerciseMerger(db).apply()), isEmpty, reason: 'idempotent');
  });

  test('a manual "off" on the duplicate moves over; the canonical\'s own choice wins', () async {
    await restoreDuplicate();
    await RankExclusions(db).set(dup, excluded: true);
    await ExerciseMerger(db).apply();
    expect((await RankExclusions(db).policy()).sourceOf(canon), RankSource.manualOff);
    await restoreDuplicate();
    await RankExclusions(db).set(canon, excluded: false);
    await RankExclusions(db).set(dup, excluded: true);
    await ExerciseMerger(db).apply();
    expect((await RankExclusions(db).policy()).sourceOf(canon), RankSource.manualOn);
  });

  test('ranks show the logged name and merge the history into one entry', () async {
    await restoreDuplicate();
    await session(canon, source: 'liftoff', displayName: 'Hip Adduction', at: DateTime.now().subtract(const Duration(days: 20)), kg: 45);
    await session(dup, source: 'app', at: DateTime.now().subtract(const Duration(days: 3)), kg: 50);
    await ExerciseMerger(db).apply();
    await RankExclusions(db).autoEnable(canon);
    final summary = await _ranks(db);
    final lifts = summary.exercises.where((e) => e.exerciseId == canon).toList();
    expect(lifts, hasLength(1));
    expect(lifts.single.name, 'Machine Seated Hip Adduction');
    expect(lifts.single.weight, 50);
  });

  test('the merge list is consistent: no chains, canonicals have a standard or muscle weights, nothing merges into itself', () async {
    final merges = await ExerciseMerger.loadAsset();
    final dups = {for (final m in merges) m.duplicate};
    expect(dups.length, merges.length, reason: 'a duplicate is listed once');
    for (final m in merges) {
      expect(m.duplicate, isNot(m.canonical));
      expect(dups.contains(m.canonical), isFalse, reason: '${m.canonical} is both a duplicate and a canonical');
    }
    final standards = await RanksRepository.loadStandards();
    final ranked = {for (final s in standards) ...s.exerciseIds};
    for (final m in merges) {
      expect(ranked.contains(m.canonical), isTrue, reason: '${m.canonical} has a strength standard');
    }
  });
}

Future<RankSummary> _ranks(AppDatabase db) async {
  final cat = await ExerciseRepository(db).watchCatalog().first;
  final history = await HistoryRepository(db).load(cat);
  final routines = await RoutineRepository(db).watchRoutines().first;
  await BodyWeightRepository(db).addManual(80, at: DateTime.now().subtract(const Duration(days: 60)));
  return RanksRepository.compute(
    history: history,
    standards: await RanksRepository.loadStandards(),
    catalog: cat,
    bodyweights: RanksRepository.timeline(await BodyWeightRepository(db).all()),
    now: DateTime.now(),
    excluded: await RankExclusions(db).load(),
    displayNames: RanksRepository.displayNamesFor(cat, [for (final r in routines) for (final e in r.exercises) (exerciseId: e.exerciseId, displayName: e.displayName)]),
  );
}
