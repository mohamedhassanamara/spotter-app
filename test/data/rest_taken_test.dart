import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/workout/data/session_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late SessionRepository repo;
  late int ex;
  final t0 = DateTime(2026, 10, 19, 9);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SessionRepository(db);
    final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(name: 'T', startedAt: t0));
    await db.into(db.exercises).insert(ExercisesCompanion.insert(id: 'x', name: 'X'));
    ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
        sessionId: sid, exerciseId: 'x', position: 0, repMin: 6, repMax: 8, targetSets: 3, restSeconds: 120));
    for (var i = 0; i < 4; i++) {
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(sessionExerciseId: ex, position: i, weight: const Value(50), reps: const Value(8)));
    }
  });
  tearDown(() => db.close());

  Future<List<WorkoutSet>> sets() => (db.select(db.workoutSets)..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
  Future<void> done(int i, DateTime at, {DateTime? skippedAt}) async =>
      repo.completeSet((await sets())[i], weight: 50, reps: 8, rpe: 9, isWarmup: false, now: at, restEndedAt: skippedAt);

  test('the first set has no rest; later ones store the actual rest: ✓ to ✓', () async {
    await done(0, t0);
    await done(1, t0.add(const Duration(minutes: 2, seconds: 14)));
    final s = await sets();
    expect(s[0].restSeconds, isNull);
    expect(s[1].restSeconds, 134, reason: '2:14');
    expect(s[2].restSeconds, isNull, reason: 'not done yet');
  });

  test('a skipped rest ends where it was skipped, not at the next ✓', () async {
    await done(0, t0);
    await done(1, t0.add(const Duration(minutes: 5)), skippedAt: t0.add(const Duration(seconds: 80)));
    expect((await sets())[1].restSeconds, 80);
    // A skip that belongs to an earlier rest (before the previous ✓) is ignored.
    await done(2, t0.add(const Duration(minutes: 7)), skippedAt: t0.add(const Duration(seconds: 80)));
    expect((await sets())[2].restSeconds, 120);
  });

  test('unticking a set clears its rest', () async {
    await done(0, t0);
    await done(1, t0.add(const Duration(seconds: 90)));
    await repo.uncompleteSet((await sets())[1].id);
    expect((await sets())[1].restSeconds, isNull);
  });

  test('drop sets and warm-ups do not get a rest of their own after a different kind of set', () async {
    await done(0, t0);
    await (db.update(db.workoutSets)..where((t) => t.position.equals(1))).write(const WorkoutSetsCompanion(setType: Value('drop')));
    await done(1, t0.add(const Duration(seconds: 20)));
    expect((await sets())[1].restSeconds, isNull, reason: 'a drop follows its set with no rest');
  });
}
