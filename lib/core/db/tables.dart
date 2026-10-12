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
}

/// One row per calendar day: raw Health metrics and the readiness computed from them.
class DailyMetrics extends Table {
  TextColumn get date => text()(); // yyyy-MM-dd
  RealColumn get hrvMs => real().nullable()();
  RealColumn get restingHr => real().nullable()();
  RealColumn get sleepMinutes => real().nullable()();
  RealColumn get activeEnergyKcal => real().nullable()();
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
