import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Exercises,
    Routines,
    RoutineExercises,
    Sessions,
    SessionExercises,
    WorkoutSets,
    DailyMetrics,
    BodyWeights,
    EgoFreezes,
    XpEvents,
    AchievementsUnlocked,
    Quests,
    AppSettings,
    MediaMatches,
    PinnedVideos,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The on-device database (Documents/spotter.sqlite).
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'spotter'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX idx_sessions_started ON sessions (started_at)');
          await customStatement('CREATE INDEX idx_session_ex_session ON session_exercises (session_id)');
          await customStatement('CREATE INDEX idx_session_ex_exercise ON session_exercises (exercise_id)');
          await customStatement('CREATE INDEX idx_sets_session_ex ON workout_sets (session_exercise_id)');
          await customStatement('CREATE INDEX idx_routine_ex_routine ON routine_exercises (routine_id)');
        },
        onUpgrade: (m, from, to) async {
          // Step by step, so any older install reaches the current version.
          if (from < 2) {
            await m.createTable(mediaMatches);
            await m.createTable(pinnedVideos);
          }
          if (from < 3) {
            await m.addColumn(routines, routines.programDay);
            await m.addColumn(routineExercises, routineExercises.programSlots);
            await m.addColumn(routineExercises, routineExercises.programRelation);
            await m.addColumn(routineExercises, routineExercises.programExercise);
            await m.addColumn(routineExercises, routineExercises.displayName);
            await m.addColumn(sessionExercises, sessionExercises.displayName);
            await m.addColumn(sessionExercises, sessionExercises.programSlots);
            await m.addColumn(sessionExercises, sessionExercises.programWeek);
            await m.addColumn(workoutSets, workoutSets.targetRepMin);
            await m.addColumn(workoutSets, workoutSets.targetRepMax);
            await m.addColumn(workoutSets, workoutSets.targetRir);
            await m.addColumn(workoutSets, workoutSets.technique);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ---- settings key/value ----

  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> putSetting(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));

  Future<void> deleteSetting(String key) => (delete(appSettings)..where((t) => t.key.equals(key))).go();

  Stream<Map<String, String>> watchSettings() =>
      select(appSettings).watch().map((rows) => {for (final r in rows) r.key: r.value});
}
