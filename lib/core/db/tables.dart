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
