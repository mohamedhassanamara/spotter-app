import '../../../core/domain/gym.dart';
import '../../coach/domain/suggestion_engine.dart' show formatKg;
import 'ranks.dart';

/// A concrete set that would reach the next rank: [reps] × [weight] kg on the exercise's own weight grid.
class RankTargetSet {
  const RankTargetSet({required this.reps, required this.weight, required this.atMax});
  final int reps;

  /// The logged load: negative for an assisted machine (assistance), 0 for bodyweight.
  final double weight;

  /// The lightest-load answer didn't exist within the max load, so this is the heaviest load with more reps.
  final bool atMax;

  /// "6 × 72.5 kg", "12 × 80 kg (max)", "8 × BW", "8 × −30 kg".
  String get text => '$reps × ${weight == 0 ? 'BW' : '${formatKg(weight).replaceFirst('-', '−')} kg'}${atMax ? ' (max)' : ''}';

  @override
  bool operator ==(Object other) => other is RankTargetSet && other.reps == reps && other.weight == weight && other.atMax == atMax;

  @override
  int get hashCode => Object.hash(reps, weight, atMax);

  @override
  String toString() => text;
}

const String rankTargetUnreachable = 'Next rank: increase max load or switch variation';

/// The set that moves an exercise to the next rank: [repMin] reps at the prescribed effort ([rir] reps in reserve) at the
/// lowest weight on [grid] (so within its max load) whose scoring e1RM reaches [targetE1rm].
///
/// Weights are the logged ones, so a lighter set is a *smaller* number: assistance is negative (−30 is easier than 0) and the
/// lowest passing weight is the most assistance that still gets there. Bodyweight lifts add [bodyweight] to the load.
/// Per-hand standards are scored per hand already, so the weight stays "per side".
/// When even the heaviest weight can't reach it in [repMin] reps, the reps needed at that weight are returned
/// (flagged [RankTargetSet.atMax]); null when more reps don't get there either (reps + RIR count up to [scoringRepCap]).
RankTargetSet? rankTargetSet({
  required StrengthStandard standard,
  required double bodyweight,
  required double targetE1rm,
  required int repMin,
  required int rir,
  required WeightGrid grid,
}) {
  if (grid.values.isEmpty || targetE1rm <= 0) return null;
  final rpe = 10.0 - rir;
  final base = standard.bodyweightLoaded ? bodyweight : 0.0;
  final reps = repMin < 1 ? 1 : repMin;
  double e1rm(double w, int r) => scoringE1rm(load: w + base, reps: r, rpe: rpe);
  const eps = 1e-6;
  for (final w in grid.values) {
    if (e1rm(w, reps) >= targetE1rm - eps) return RankTargetSet(reps: reps, weight: w, atMax: false);
  }
  final top = grid.values.last;
  for (var r = reps + 1; r + rir <= scoringRepCap; r++) {
    if (e1rm(top, r) >= targetE1rm - eps) return RankTargetSet(reps: r, weight: top, atMax: true);
  }
  return null;
}

/// "6 × 72.5 kg → Gold 2", or [rankTargetUnreachable]; null when there is no next rank.
String? rankTargetLine(RankTargetSet? set, String? nextLabel) {
  if (nextLabel == null) return null;
  return set == null ? rankTargetUnreachable : '${set.text} → $nextLabel';
}
