import '../../../core/db/database.dart' show WorkoutSet;
import '../../workout/domain/set_kinds.dart';
import 'ranks.dart';

/// Everything the logger's rank row shows for ONE exercise id. Derived (never stored, never cached per workout) by
/// `exerciseRankStateProvider` from: the finished history (the baseline), the completed sets of the running workout,
/// the exercise's standard (hand-made or estimated), the bodyweight and the "counts toward rank" switch.
class ExerciseRankState {
  const ExerciseRankState({
    required this.exerciseId,
    required this.hidden,
    required this.standard,
    required this.baseline,
    required this.score,
    required this.bodyweight,
  });

  final String exerciseId;

  /// Switched off by hand ("Counts toward rank" off).
  final bool hidden;

  /// Null only for an id that is not in the library at all.
  final StrengthStandard? standard;

  /// Best finished-history rank of the exercise, if any.
  final ExerciseRank? baseline;

  /// Best of the history and this workout's valid completed sets; null = unranked (nothing valid logged yet).
  final RankScore? score;

  /// Latest bodyweight; 0 = not set.
  final double bodyweight;

  bool get estimated => standard?.estimated ?? false;
  bool get hasBodyweight => bodyweight > 0;
  bool get ranked => score != null;

  /// The rank the exercise works towards: the next division, or Bronze 1 when unranked.
  String? get nextLabel => score == null ? '${Tier.bronze.label} 1' : score!.nextLabel;

  /// e1RM (kg, bodyweight included for bodyweight lifts) that reaches [nextLabel]; null at the top or without bodyweight/standard.
  double? get nextE1rm {
    final std = standard;
    if (std == null || !hasBodyweight) return null;
    final s = score;
    if (s == null) return std.thresholds[Tier.bronze.index] * std.normalizer(bodyweight);
    return std.nextThresholdKg(s, bodyweight);
  }
}

/// A set that counts for the rank of its exercise: completed, a working set (no warm-up, drop, myo or hold), with reps,
/// and not an ego set (heavier than suggested AND below the rep range).
bool countsForRank(WorkoutSet set) =>
    set.completed && set.isWorkingSet && set.reps > 0 && !(set.isOverride && set.reps < (set.targetRepMin ?? 0));

/// The best score of [baseline] and the [sets] of the running workout, each scored at [bodyweight]. Null when neither has one.
RankScore? liveScore({required RankScore? baseline, required StrengthStandard? standard, required double bodyweight, required Iterable<WorkoutSet> sets}) {
  var best = baseline;
  if (standard == null || bodyweight <= 0) return best;
  for (final set in sets) {
    if (!countsForRank(set)) continue;
    final load = set.weight + (standard.bodyweightLoaded ? bodyweight : 0);
    final e = scoringE1rm(load: load, reps: set.reps, rpe: set.rpe);
    if (e <= 0) continue;
    final score = standard.scoreForRatio(standard.ratioFor(e, bodyweight));
    if (best == null || score.value > best.value) best = score;
  }
  return best;
}
