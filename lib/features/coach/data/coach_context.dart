import '../../../core/db/database.dart';
import '../../../core/domain/equipment.dart';
import '../../../core/domain/gym.dart';
import '../../../core/domain/history.dart';
import '../../../core/domain/muscles.dart';
import '../../../core/domain/training.dart';
import '../../library/domain/exercise_info.dart';
import '../../library/domain/load_kinds.dart';
import '../../readiness/domain/readiness.dart';
import '../../recovery/domain/recovery.dart';
import '../domain/energy.dart';
import '../domain/suggestion_engine.dart';

class EgoFreezeRepository {
  EgoFreezeRepository(this._db);
  final AppDatabase _db;

  Stream<List<EgoFreeze>> watchAll() => _db.select(_db.egoFreezes).watch();

  Future<List<EgoFreeze>> all() => _db.select(_db.egoFreezes).get();

  Future<void> add({required String exerciseId, required DateTime start, required DateTime until, required double baseWeight, required String reason}) =>
      _db.into(_db.egoFreezes).insert(EgoFreezesCompanion.insert(
            exerciseId: exerciseId,
            startedAt: start,
            until: until,
            baseWeight: baseWeight,
            reason: reason,
          ));

  Future<void> deleteAll() => _db.delete(_db.egoFreezes).go();
}

/// Most recent freeze per exercise.
Map<String, EgoFreeze> latestFreezes(Iterable<EgoFreeze> rows) {
  final out = <String, EgoFreeze>{};
  for (final f in rows) {
    final cur = out[f.exerciseId];
    if (cur == null || f.startedAt.isAfter(cur.startedAt)) out[f.exerciseId] = f;
  }
  return out;
}

/// Turns today's readiness + training load into the per-exercise readiness the engine uses.
ExerciseReadiness exerciseReadiness(ReadinessResult? today, Set<Muscle> overloaded, MuscleTargets targets) {
  final score = today?.coachScore ?? ReadinessCalculator.neutralScore;
  final groups = [
    for (final g in targets.primary)
      if (overloaded.contains(g)) g.label,
  ];
  return ExerciseReadiness(score: score, calibrating: today?.calibrating ?? false, loadPenaltyGroups: groups);
}

/// Everything the suggestion engine needs at a point in time.
class CoachContext {
  CoachContext({
    required this.history,
    required this.readiness,
    required this.overloaded,
    required this.freezes,
    required this.increments,
    required this.now,
    this.bodyweight = 0,
    this.bodyweightLoaded = const {},
    this.gym = GymEquipment.defaults,
    this.energy = EnergyContext.none,
    this.recovery,
    this.formResets = const {},
  });

  final TrainingHistory history;
  final ReadinessResult? readiness;
  final Set<Muscle> overloaded;
  final Map<String, EgoFreeze> freezes;
  final Increments increments;
  final DateTime now;

  /// Latest bodyweight and the exercises whose load is relative to it (pull-ups, dips, assisted).
  final double bodyweight;
  final Set<String> bodyweightLoaded;

  /// Settings → My gym equipment: suggestions only land on weights that exist.
  final GymEquipment gym;

  /// Bodyweight trend and nutrition (Apple Health).
  final EnergyContext energy;

  /// Muscle recovery now; Fatigued prime movers may soften a suggestion by one step.
  final RecoveryState? recovery;
  final Map<String, FormReset> formResets;

  /// The loads that exist for [info]: the gym's grid plus every weight logged on it.
  WeightGrid gridFor(ExerciseInfo info) => gridForExercise(gym, history, info);

  static const _engine = SuggestionEngine();

  FreezeState? freezeFor(String exerciseId) {
    final f = freezes[exerciseId];
    if (f == null) return null;
    final s = FreezeState(until: f.until, baseWeight: f.baseWeight);
    return s.isActive(now) ? s : null;
  }

  Suggestion suggest(ExerciseInfo info, RepRange range, int targetSets, int targetRir) => _engine.suggest(SuggestionInput(
        range: range,
        targetSets: targetSets,
        targetRir: targetRir,
        increment: increments.of(info.equipmentKind),
        equipment: info.equipmentKind,
        history: history.logsForRange(info.id, range),
        readiness: exerciseReadiness(readiness, overloaded, info.targets),
        now: now,
        freeze: freezeFor(info.id),
        bodyweight: bodyweightLoaded.contains(info.id) ? bodyweight : 0,
        assisted: isAssisted(info.id),
        rangeMatched: history.logsFor(info.id).isEmpty || history.hasLogsAtRange(info.id, range),
        grid: gridFor(info),
        compound: info.isCompound,
        fatigued: [
          if (recovery != null)
            for (final m in fatiguedPrimaries(recovery!, [info.targets])) m.label,
        ],
        energy: energy,
        formReset: formResets[info.id],
      ));
}

/// The loads that exist for [info]: the gym's grid plus every working weight you've logged on it.
WeightGrid gridForExercise(GymEquipment gym, TrainingHistory history, ExerciseInfo info) => gym.gridFor(
      exerciseId: info.id,
      kind: info.equipmentKind,
      assisted: isAssisted(info.id),
      logged: [for (final l in history.logsFor(info.id)) for (final s in l.sets) if (!s.isWarmup) snapNoise(s.weight)],
    );

/// Working sets per session exercise, attributed to its primary groups (training-load modifier).
List<GroupSetEntry> groupSetEntries(TrainingHistory history) => [
      for (final s in history.sessions)
        for (final e in s.exercises)
          if (e.workingSets.isNotEmpty)
            GroupSetEntry(date: s.startedAt, groups: e.targets.primary, sets: e.workingSets.length),
    ];
