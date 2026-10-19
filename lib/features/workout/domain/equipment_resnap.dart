import '../../../core/db/database.dart';
import '../../../core/domain/gym.dart';
import '../../coach/domain/suggestion_engine.dart' show formatKg;

/// What a Weight steps change does to one set that is not done yet.
class SetResnap {
  const SetResnap({required this.setId, required this.weight, required this.suggested, required this.from, required this.reason});
  final int setId;
  final double weight;
  final double? suggested;
  final double from;
  final String reason;
}

/// The not-yet-completed sets of an exercise after its grid changed: each weight snaps to the nearest load of the new [grid] (which already stops at the max load).
/// A set still at the old suggestion takes the new one ([newSuggested]); a weight you typed is only snapped. Completed sets never appear.
/// A set that already is on the grid, and below the cap, is not touched.
List<SetResnap> planResnap({
  required Iterable<WorkoutSet> sets,
  required WeightGrid grid,
  required double? oldSuggested,
  required double? newSuggested,
}) {
  final out = <SetResnap>[];
  for (final s in sets) {
    if (s.completed) continue;
    final untouched = !s.isWarmup && oldSuggested != null && (s.weight - oldSuggested).abs() < 0.01 && newSuggested != null;
    final wanted = untouched ? newSuggested : s.weight;
    var w = grid.snap(wanted);
    final max = grid.maxLoad;
    if (max != null && w > max) w = max;
    final changed = (w - s.weight).abs() >= 0.01;
    final sugg = s.suggestedWeight == null ? null : (untouched ? w : grid.snap(s.suggestedWeight!));
    final suggChanged = sugg != null && (sugg - (s.suggestedWeight ?? sugg)).abs() >= 0.01;
    if (!changed && !suggChanged) continue;
    final capped = max != null && s.weight > max + 0.01;
    out.add(SetResnap(
      setId: s.id,
      weight: w,
      suggested: sugg,
      from: s.adjustedFrom ?? s.weight,
      reason: changed
          ? 'Weight steps updated: ${formatKg(s.weight)} kg is now ${formatKg(w)} kg'
              '${capped ? ' (the max load is ${formatKg(max)} kg)' : ' (the nearest weight on the new steps)'}.'
          : 'Weight steps updated.',
    ));
  }
  return out;
}
