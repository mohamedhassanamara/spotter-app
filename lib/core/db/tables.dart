import 'package:drift/drift.dart';

/// Exercise catalogue: free-exercise-db entries plus custom exercises.
class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get primaryMuscles => text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get secondaryMuscles => text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get equipment => text().nullable()();
  TextColumn get level => text().nullable()();
  TextColumn get mechanic => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get instructions => text().withDefault(const Constant('[]'))(); // JSON list
  TextColumn get images => text().withDefault(const Constant('[]'))(); // JSON list of repo paths
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();

  /// v7: full image URLs from other free sources (wger), after the free-exercise-db [images].
  TextColumn get extraImages => text().withDefault(const Constant('[]'))();

  /// v7: fedb (free-exercise-db) | wger | edb_v1 | custom.
  TextColumn get source => text().nullable()();

  /// v7: JSON licence/author credits of the merged sources.
  TextColumn get credit => text().nullable()();

  /// v7: this exercise's own ExerciseDB V1 GIF id (V1 entries, or a merged duplicate).
  TextColumn get edbV1Id => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Routines extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  /// v3: program day this routine runs (e.g. "upper"), if it follows a program.
  TextColumn get programDay => text().nullable()();
}

class RoutineExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get routineId => integer().references(Routines, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get position => integer()();
  IntColumn get repMin => integer()();
  IntColumn get repMax => integer()();
  IntColumn get targetSets => integer()();
  IntColumn get restSeconds => integer()();
  IntColumn get targetRir => integer().withDefault(const Constant(2))();

  /// v3: program slot ids (JSON list) this row takes its prescription from, in order.
  TextColumn get programSlots => text().nullable()();

  /// v3: program | substitution | swap | extra.
  TextColumn get programRelation => text().nullable()();

  /// v3: the program's exercise name this row stands in for.
  TextColumn get programExercise => text().nullable()();

  /// v3: the owner's name for the exercise (e.g. "Chest Press" for Leverage_Chest_Press).
  TextColumn get displayName => text().nullable()();

  /// v8: rep range set in the routine editor (or "Update routine"), overriding the program's per-set
  /// ranges for this routine. Null = follow the program.
  IntColumn get overrideRepMin => integer().nullable()();
  IntColumn get overrideRepMax => integer().nullable()();

  /// v8: superset group within the routine (A1/A2…).
  IntColumn get supersetGroup => integer().nullable()();
}

class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get routineId => integer().nullable()();
  TextColumn get name => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active | finished
  IntColumn get readinessScore => integer().nullable()();
  TextColumn get readinessBand => text().nullable()();
  BoolColumn get healthSynced => boolean().withDefault(const Constant(false))();
  IntColumn get xpEarned => integer().withDefault(const Constant(0))();

  /// v4: app | liftoff. Imported sessions count for history, PRs and ranks but not for
  /// discipline/override stats or XP.
  TextColumn get source => text().withDefault(const Constant('app'))();

  /// v4: the source's id for the session (Liftoff: its Date string), unique, so re-imports skip it.
  TextColumn get externalId => text().nullable()();
}

class SessionExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get position => integer()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get repMin => integer()();
  IntColumn get repMax => integer()();
  IntColumn get targetSets => integer()();
  IntColumn get restSeconds => integer()();
  IntColumn get targetRir => integer().withDefault(const Constant(2))();
  TextColumn get suggestionKind => text().withDefault(const Constant('none'))();
  RealColumn get suggestedWeight => real().nullable()();
  IntColumn get suggestedReps => integer().nullable()();
  IntColumn get suggestedSets => integer().nullable()();
  TextColumn get suggestionJson => text().nullable()(); // headline + why lines

  /// v3: program slots and the program week this session used.
  TextColumn get programSlots => text().nullable()();
  IntColumn get programWeek => integer().nullable()();

  /// v3: the owner's name for the exercise, copied from the routine.
  TextColumn get displayName => text().nullable()();

  /// v5: rest timer on/off for this exercise in this workout.
  BoolColumn get restEnabled => boolean().withDefault(const Constant(true))();

  /// v5: exercises sharing a group number form a superset (A1/A2…).
  IntColumn get supersetGroup => integer().nullable()();

  /// v8: the routine row this came from (null when added mid-workout), for "Update routine".
  IntColumn get routineExerciseId => integer().nullable()();

  /// v8: target reps were changed mid-workout ([repMin]–[repMax] then holds the new range).
  BoolColumn get targetsEdited => boolean().withDefault(const Constant(false))();
}

class WorkoutSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionExerciseId => integer().references(SessionExercises, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();
  RealColumn get weight => real().withDefault(const Constant(0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  RealColumn get rpe => real().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  RealColumn get suggestedWeight => real().nullable()();
  IntColumn get suggestedReps => integer().nullable()();
  BoolColumn get isOverride => boolean().withDefault(const Constant(false))();
  TextColumn get overrideReason => text().nullable()();

  /// v3: per-set prescription (program sets can differ within one exercise, e.g. 2×4-6 then 1×20).
  IntColumn get targetRepMin => integer().nullable()();
  IntColumn get targetRepMax => integer().nullable()();
  IntColumn get targetRir => integer().nullable()();

  /// v3: last-set intensity technique id (e.g. drop_sets_2x25), on the set it applies to.
  TextColumn get technique => text().nullable()();

  /// v5: null = a normal set (warm-up or working per [isWarmup]); 'drop' = a drop set under the set
  /// before it. Drop sets count for volume, never for e1RM, ranks or PRs. v8 adds 'myo' and 'hold'.
  TextColumn get setType => text().nullable()();

  /// v9: section 7's "+ partials": partial reps after the last full rep. Informational only (the
  /// full reps are what count).
  BoolColumn get partials => boolean().withDefault(const Constant(false))();

  /// v11: the weight this set was planned at before an earlier set of the same exercise (this workout)
  /// changed it; null = the plan is untouched. [adjustReason] says why, for the marker's explanation.
  RealColumn get adjustedFrom => real().nullable()();
  TextColumn get adjustReason => text().nullable()();

  /// v12: the rest actually taken before this set, in seconds: from the previous set's ✓ to this ✓, or to the moment the rest
  /// timer was skipped. Null for a first set, warm-ups after nothing, or an unticked set.
  IntColumn get restSeconds => integer().nullable()();
}

/// One row per calendar day: raw Health metrics and the readiness computed from them.
class DailyMetrics extends Table {
  TextColumn get date => text()(); // yyyy-MM-dd
  RealColumn get hrvMs => real().nullable()();
  RealColumn get restingHr => real().nullable()();
  RealColumn get sleepMinutes => real().nullable()();
  RealColumn get activeEnergyKcal => real().nullable()();

  /// v10: food logged in Health that day (kcal, protein g); null when nothing was logged.
  RealColumn get dietaryKcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  IntColumn get readinessScore => integer().nullable()();
  TextColumn get readinessBand => text().nullable()();
  BoolColumn get calibrating => boolean().withDefault(const Constant(true))();
  TextColumn get explanation => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

class BodyWeights extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get measuredAt => dateTime()();
  RealColumn get kg => real()();
  TextColumn get source => text()(); // health | manual
}

class EgoFreezes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get exerciseId => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get until => dateTime()();
  RealColumn get baseWeight => real()();
  TextColumn get reason => text()();
}

class XpEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get at => dateTime()();
  IntColumn get amount => integer()();
  TextColumn get reason => text()();
  IntColumn get sessionId => integer().nullable()();
  TextColumn get weekStart => text().nullable()(); // yyyy-MM-dd for weekly bonuses
}

class AchievementsUnlocked extends Table {
  TextColumn get key => text()();
  DateTimeColumn get unlockedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Quests extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get weekStart => text()(); // yyyy-MM-dd (Monday)
  TextColumn get key => text()();
  TextColumn get params => text().withDefault(const Constant('{}'))();
  TextColumn get title => text()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Schema v2: which ExerciseDB V1 animation demonstrates each library exercise.
@DataClassName('MediaMatchRow')
class MediaMatches extends Table {
  TextColumn get exerciseId => text()();

  /// Null when nothing matched (or a manual override says "no demo").
  TextColumn get edbId => text().nullable()();
  TextColumn get edbName => text().nullable()();
  TextColumn get gifUrl => text().nullable()();
  RealColumn get confidence => real().withDefault(const Constant(0))();

  /// auto | override (assets/media_overrides.json) | manual (picked in the debug screen)
  TextColumn get source => text().withDefault(const Constant('auto'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {exerciseId};
}

/// Schema v2: a YouTube tutorial pinned to an exercise.
class PinnedVideos extends Table {
  TextColumn get exerciseId => text()();
  TextColumn get videoId => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get channel => text().withDefault(const Constant(''))();
  IntColumn get startSeconds => integer().withDefault(const Constant(0))();
  DateTimeColumn get pinnedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {exerciseId};
}

/// Schema v6: our exercise → ExerciseDB V2 exerciseId. Exercise IDs are stable and may be kept
/// permanently (AscendAPI caching policy); media URLs and text never live here.
@DataClassName('EdbV2Map')
class EdbV2Maps extends Table {
  TextColumn get exerciseId => text()();

  /// Null while queued or when nothing fits.
  TextColumn get edbId => text().nullable()();

  /// auto (high-confidence) | confirmed (picked in the debug screen) | queued (needs review) | none
  TextColumn get status => text()();
  RealColumn get confidence => real().withDefault(const Constant(0))();

  /// The search term used.
  TextColumn get query => text().withDefault(const Constant(''))();

  /// Queued items: top candidates as JSON [{id, name, score}] for the review screen.
  TextColumn get candidates => text().withDefault(const Constant('[]'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {exerciseId};
}
