import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/workout/data/history_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('suspect sets: completed working sets whose saved numbers are exactly the suggestion; correcting one clears it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final at = DateTime(2026, 10, 12, 18);
    await db.into(db.exercises).insert(ExercisesCompanion.insert(id: 'x', name: 'X', primaryMuscles: const Value('[]'), secondaryMuscles: const Value('[]'), instructions: const Value('[]'), images: const Value('[]')));
    final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(name: 'Upper', startedAt: at, status: const Value('finished')));
    final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
          sessionId: sid, exerciseId: 'x', position: 0, repMin: 6, repMax: 8, targetSets: 4, restSeconds: 90));
    Future<int> set(int pos, double w, int reps, {double? sw, int? sr, bool completed = true, bool warmup = false, String? type}) =>
        db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
              sessionExerciseId: ex,
              position: pos,
              weight: Value(w),
              reps: Value(reps),
              suggestedWeight: Value(sw),
              suggestedReps: Value(sr),
              completed: Value(completed),
              isWarmup: Value(warmup),
              setType: Value(type),
            ));
    final same = await set(0, 40, 8, sw: 40, sr: 8); // exactly the suggestion
    await set(1, 42.5, 8, sw: 40, sr: 8); // typed a different weight
    await set(2, 40, 7, sw: 40, sr: 8); // typed different reps
    await set(3, 20, 5, sw: 20, sr: 5, warmup: true); // warm-ups aren't checked
    await set(4, 30, 10, sw: 30, sr: 10, type: 'drop'); // follow-ups aren't checked
    await set(5, 40, 8, sw: 40, sr: 8, completed: false); // never completed
    await set(6, 40, 8); // no suggestion (calibration): can't tell

    final repo = HistoryRepository(db);
    expect(await repo.suspectSetIds(sid), {same});

    await repo.correctSet(same, weight: 37.5, reps: 9);
    final row = await (db.select(db.workoutSets)..where((t) => t.id.equals(same))).getSingle();
    expect((row.weight, row.reps), (37.5, 9));
    expect(await repo.suspectSetIds(sid), isEmpty);

    await HistoryRepository.markSavedValuesFixed(db, DateTime(2026, 10, 13, 9));
    await HistoryRepository.markSavedValuesFixed(db, DateTime(2026, 11, 1));
    expect(await repo.savedValuesFixedAt(), DateTime(2026, 10, 13, 9), reason: 'written once, on the first launch of this build');
    await db.close();
  });
}
