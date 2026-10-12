import 'dart:math' as math;

import 'dates.dart';
import 'equipment.dart';
import 'muscles.dart';
import 'training.dart';

/// A logged set with its identity and timing (history display, export).
class HistSet {
  const HistSet({required this.id, required this.set, required this.completedAt, this.overrideReason, this.targetRange});
  final int id;
  final LoggedSet set;
  final DateTime? completedAt;
  final String? overrideReason;

  /// Per-set prescribed rep range (program sets can differ within one exercise).
  final RepRange? targetRange;
}

class HistExercise {
  const HistExercise({
    required this.id,
    required this.exerciseId,
    required this.name,
    required this.targets,
    required this.equipment,
    required this.range,
    required this.targetSets,
    required this.suggestionKind,
    this.techniqueDay = false,
    required this.suggestedWeight,
    required this.suggestedReps,
    required this.notes,
    required this.sets,
  });

  final int id;
  final String exerciseId;
  final String name;
  final MuscleTargets targets;
  final EquipmentKind equipment;
  final RepRange range;
  final int targetSets;
  final SuggestionKind suggestionKind;
  final bool techniqueDay;
  final double? suggestedWeight;
  final int? suggestedReps;
  final String notes;
  final List<HistSet> sets;

  List<LoggedSet> get loggedSets => [for (final s in sets) s.set];
  List<LoggedSet> get workingSets => [for (final s in sets) if (s.set.isWorking) s.set];
}

class HistSession {
  const HistSession({
    required this.id,
    required this.name,
    required this.routineId,
    required this.startedAt,
    required this.endedAt,
    required this.notes,
    required this.readinessScore,
    required this.readinessBand,
    required this.xpEarned,
    required this.exercises,
    this.imported = false,
  });

  final int id;
  final String name;
  final int? routineId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String notes;
  final int? readinessScore;
  final String? readinessBand;
  final int xpEarned;
  final List<HistExercise> exercises;

  /// Came from the Liftoff import (no suggestions, no XP).
  final bool imported;

  Duration get duration => (endedAt ?? startedAt).difference(startedAt);

  Iterable<LoggedSet> get workingSets => exercises.expand((e) => e.workingSets);

  double get volume => workingSets.fold<double>(0, (v, s) => v + s.weight * s.reps);

  bool get hasOverrides => workingSets.any((s) => s.isOverride);
}

/// All finished sessions, oldest first, with fast per-exercise access.
class TrainingHistory {
  TrainingHistory(List<HistSession> sessions)
      : sessions = [...sessions]..sort((a, b) => a.startedAt.compareTo(b.startedAt)) {
    for (final s in this.sessions) {
      for (final e in s.exercises) {
        (_byExercise[e.exerciseId] ??= []).add(ExerciseSessionLog(
          sessionId: s.id,
          date: s.startedAt,
          sets: e.loggedSets,
          suggestionKind: e.suggestionKind,
          techniqueDay: e.techniqueDay,
        ));
      }
    }
  }

  static final empty = TrainingHistory(const []);

  final List<HistSession> sessions;
  final Map<String, List<ExerciseSessionLog>> _byExercise = {};

  /// Chronological logs of one exercise.
  List<ExerciseSessionLog> logsFor(String exerciseId) => _byExercise[exerciseId] ?? const [];

  /// Logs of one exercise restricted to sets prescribed at [range] (a set without its own target
  /// uses its exercise's range). Falls back to all logs when nothing was ever done at that range,
  /// so a new back-off slot still starts from real history.
  List<ExerciseSessionLog> logsForRange(String exerciseId, RepRange range) {
    final out = <ExerciseSessionLog>[];
    for (final s in sessions) {
      for (final e in s.exercises) {
        if (e.exerciseId != exerciseId) continue;
        final sets = [for (final h in e.sets) if ((h.targetRange ?? e.range) == range) h.set];
        if (!sets.any((x) => x.isWorking)) continue;
        out.add(ExerciseSessionLog(
          sessionId: s.id,
          date: s.startedAt,
          sets: sets,
          suggestionKind: e.suggestionKind,
          techniqueDay: e.techniqueDay,
        ));
      }
    }
    return out.isEmpty ? logsFor(exerciseId) : out;
  }

  /// Whether any working set of [exerciseId] was prescribed at [range].
  bool hasLogsAtRange(String exerciseId, RepRange range) => sessions.any((s) => s.exercises.any((e) =>
      e.exerciseId == exerciseId && e.sets.any((h) => h.set.isWorking && (h.targetRange ?? e.range) == range)));

  Iterable<String> get exerciseIds => _byExercise.keys;

  Map<String, List<ExerciseSessionLog>> get logsByExercise => _byExercise;

  TrainingHistory without(int sessionId) => TrainingHistory(sessions.where((s) => s.id != sessionId).toList());

  TrainingHistory before(DateTime t) => TrainingHistory(sessions.where((s) => s.startedAt.isBefore(t)).toList());

  /// Best valid e1RM per exercise for sessions in [from, to].
  Map<String, double> bestValidE1rm({
    DateTime? from,
    DateTime? to,
    Set<String> bodyweightLoaded = const {},
    double bodyweight = 0,
  }) {
    final out = <String, double>{};
    for (final s in sessions) {
      if (from != null && s.startedAt.isBefore(from)) continue;
      if (to != null && s.startedAt.isAfter(to)) continue;
      for (final e in s.exercises) {
        final bw = bodyweightLoaded.contains(e.exerciseId) ? bodyweight : 0.0;
        for (final set in e.workingSets) {
          if (!set.isValidForRecords) continue;
          final v = set.e1rm(bodyweight: bw);
          out[e.exerciseId] = math.max(out[e.exerciseId] ?? 0, v);
        }
      }
    }
    return out;
  }

  Iterable<HistSession> inRange(DateTime from, DateTime to) =>
      sessions.where((s) => !s.startedAt.isBefore(from) && s.startedAt.isBefore(to));

  Iterable<HistSession> inWeek(DateTime anyDay) {
    final ws = weekStart(anyDay);
    return inRange(ws, addDays(ws, 7));
  }

  List<LoggedSet> setsSince(DateTime from) =>
      [for (final s in sessions) if (!s.startedAt.isBefore(from)) ...s.workingSets];
}
