import '../../coach/domain/suggestion_engine.dart' show formatKg;
import 'rank_target.dart';
import 'ranks.dart';

/// How far from the current bodyweight a "what if" may go: ±10%.
const double whatIfBand = 0.10;

/// The bodyweights a projection may use around [current] (7-day average).
({double min, double max}) whatIfRange(double current) => (min: current * (1 - whatIfBand), max: current * (1 + whatIfBand));

/// Slider bounds on a 0.5 kg grid, always inside [whatIfRange].
({double min, double max}) whatIfSliderRange(double current) {
  final r = whatIfRange(current);
  return (min: (r.min * 2).ceil() / 2, max: (r.max * 2).floor() / 2);
}

enum BodyweightOutcome {
  /// [BodyweightTarget.bodyweight] reaches the next rank.
  reachable,

  /// Not within the ±10% band (or bodyweight doesn't move this rank at all).
  unreachable,

  /// More bodyweight lowers the rank, so there is no gain to chase that way.
  worse,

  /// No next rank (top of the ladder) or no bodyweight to start from.
  none,
}

class BodyweightTarget {
  const BodyweightTarget(this.outcome, [this.bodyweight]);
  final BodyweightOutcome outcome;
  final double? bodyweight;

  static const none = BodyweightTarget(BodyweightOutcome.none);

  @override
  bool operator ==(Object other) => other is BodyweightTarget && other.outcome == outcome && other.bodyweight == bodyweight;

  @override
  int get hashCode => Object.hash(outcome, bodyweight);

  @override
  String toString() => 'BodyweightTarget($outcome, $bodyweight)';
}

const String bodyweightUnreachable = 'Not reachable by bodyweight alone';
const String bodyweightWorse = 'More bodyweight would lower this rank';

/// The lowest bodyweight within [current] … +10% at which [score] (rank points at a bodyweight) reaches [target] points.
///
/// [score] is monotone in bodyweight for every standard (allometric and plain-ratio lifts fall with it, assisted lifts
/// rise), so it is bisected numerically instead of inverting each formula. The answer is rounded up to 0.5 kg so it
/// really reaches the target.
BodyweightTarget solveBodyweight({required double Function(double bw) score, required double target, required double current}) {
  if (current <= 0) return BodyweightTarget.none;
  const eps = 1e-9;
  final max = whatIfRange(current).max;
  final here = score(current);
  if (score(max) < here - eps) return const BodyweightTarget(BodyweightOutcome.worse);
  if (here >= target - eps) return BodyweightTarget(BodyweightOutcome.reachable, current);
  if (score(max) < target - eps) return const BodyweightTarget(BodyweightOutcome.unreachable);
  var lo = current, hi = max;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (score(mid) >= target - eps) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  // The scale and the slider work in 0.5 kg, so the answer is rounded up to it: it never undershoots the target.
  var bw = (hi * 2).ceil() / 2;
  while (score(bw) < target - eps) {
    bw += 0.5;
  }
  return BodyweightTarget(BodyweightOutcome.reachable, bw);
}

double _nextPoints(RankScore s) => (s.value + 1e-9).floorToDouble() + 1;

/// The bodyweight at which [rank]'s best set would reach its next division.
BodyweightTarget bodyweightTargetFor(ExerciseRank rank, double current) =>
    rank.score.isApex ? BodyweightTarget.none : solveBodyweight(score: (bw) => rank.atBodyweight(bw).score.value, target: _nextPoints(rank.score), current: current);

/// The bodyweight at which [muscle]'s rank (all its lifts re-scored together) would reach its next division.
BodyweightTarget bodyweightTargetForMuscle(MuscleRank muscle, double current) {
  if (muscle.score.isApex) return BodyweightTarget.none;
  final totalW = muscle.contributions.fold<double>(0, (a, c) => a + c.weight);
  double at(double bw) => muscle.contributions.fold<double>(0, (a, c) => a + c.rank.atBodyweight(bw).score.value * c.weight) / totalW;
  return solveBodyweight(score: at, target: _nextPoints(muscle.score), current: current);
}

/// "Your 6 × 70 kg at 101 kg bodyweight → Gold 2", or why there is no such target. Always a projection, never advice.
String? bodyweightTargetLine(ExerciseRank rank, BodyweightTarget t, String? nextLabel) {
  if (nextLabel == null) return null;
  return switch (t.outcome) {
    BodyweightOutcome.none => null,
    BodyweightOutcome.unreachable => bodyweightUnreachable,
    BodyweightOutcome.worse => bodyweightWorse,
    BodyweightOutcome.reachable =>
      'Your ${RankTargetSet(reps: rank.reps, weight: rank.weight, atMax: false).text} at ${formatKg(t.bodyweight!)} kg bodyweight → $nextLabel',
  };
}

/// Muscle version: "At 101 kg bodyweight → Gold 2 for Chest".
String? muscleBodyweightTargetLine(BodyweightTarget t, String? nextLabel, String muscleLabel) {
  if (nextLabel == null) return null;
  return switch (t.outcome) {
    BodyweightOutcome.none => null,
    BodyweightOutcome.unreachable => bodyweightUnreachable,
    BodyweightOutcome.worse => bodyweightWorse,
    BodyweightOutcome.reachable => 'Your current lifts at ${formatKg(t.bodyweight!)} kg bodyweight → $nextLabel for $muscleLabel',
  };
}
