import '../../coach/domain/suggestion_engine.dart' show formatKg;
import 'rank_target.dart';
import 'ranks.dart';

/// The explanation of bodyweight mode, shown once in the rank detail sheet.
const String bodyweightModeNote =
    'In this mode your rank compares weight lifted to your bodyweight, so gaining bodyweight without lifting more can lower it.';

const String setBodyweightText = 'Set your bodyweight';

/// "1.12x BW": the best set's e1RM (bodyweight included for bodyweight lifts, the engine's own best-set measure) over bodyweight.
String ratioText(double ratio) => '${ratio.toStringAsFixed(2)}x BW';

/// Current relative strength of [score] on [standard] at [bodyweight]: e1RM ÷ bodyweight. Null when unranked or without bodyweight.
double? relativeStrength({required RankScore? score, required StrengthStandard? standard, required double bodyweight}) {
  if (score == null || standard == null || bodyweight <= 0) return null;
  return standard.ratioForPoints(score.value) * standard.normalizer(bodyweight) / bodyweight;
}

/// What the rank row's second line says. [line] is the one line; [detail] is the full text for the sheet (same words, no cut).
class RankRowText {
  const RankRowText(this.line, {this.needsBodyweight = false, this.isTop = false});
  final String line;

  /// "Set your bodyweight": tapping opens the bodyweight input.
  final bool needsBodyweight;
  final bool isTop;

  @override
  String toString() => line;
}

/// Lift mode: "6 × 72.5 kg → Gold 2". Bodyweight mode: "1.12x BW → Gold 2: 6 × 1.05x BW (about 72.5 kg at 69 kg)".
///
/// - [hidden]: switched off by hand. [bodyweight] 0 = not set. [score] null = unranked (the target is then [nextLabel], Bronze 1).
/// - [set] is the set that reaches [nextLabel] on the exercise's weight grid (null = unreachable); [setKnown] false while the grid is not loaded yet.
/// - In bodyweight mode the ratios are on the *total* load (bodyweight included for bodyweight lifts), the kg figure is the same total.
RankRowText buildRankRowText({
  required bool hidden,
  required bool bodyweightMode,
  required double bodyweight,
  required RankScore? score,
  required StrengthStandard? standard,
  required String? nextLabel,
  required RankTargetSet? set,
  bool setKnown = true,
}) {
  if (hidden) return const RankRowText('Hidden from ranks');
  if (bodyweight <= 0) return const RankRowText(setBodyweightText, needsBodyweight: true);
  if (score != null && score.isApex) return const RankRowText('Top of the ladder', isTop: true);
  if (nextLabel == null || !setKnown) return const RankRowText('');
  if (set == null) return const RankRowText(rankTargetUnreachable);
  if (!bodyweightMode) return RankRowText(rankTargetLine(set, nextLabel)!);
  final load = set.weight + (standard?.bodyweightLoaded == true ? bodyweight : 0);
  final now = relativeStrength(score: score, standard: standard, bodyweight: bodyweight);
  final target = '$nextLabel: ${set.reps} × ${ratioText(load / bodyweight)} (about ${formatKg(load)} kg at ${formatKg(bodyweight)} kg)';
  return RankRowText(now == null ? '→ $target' : '${ratioText(now)} → $target');
}
