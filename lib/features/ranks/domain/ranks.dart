import '../../../core/domain/muscle_group.dart';

enum Tier {
  iron('Iron'),
  bronze('Bronze'),
  silver('Silver'),
  gold('Gold'),
  platinum('Platinum'),
  diamond('Diamond'),
  champion('Champion');

  const Tier(this.label);
  final String label;
}

/// A rank position as a continuous score in [0, 7): integer part = tier, fraction = progress in tier.
class RankScore {
  RankScore(double value) : value = value.clamp(0.0, Tier.values.length - 1e-6);

  final double value;

  // Floors use a small epsilon so a score sitting on a boundary (or an average of identical
  // scores that lost an ulp) never drops into the previous division.
  static const double _eps = 1e-9;

  int get _tierIndex => (value + _eps).floor().clamp(0, Tier.values.length - 1);

  Tier get tier => Tier.values[_tierIndex];

  /// Progress within the tier, 0..1.
  double get tierProgress => (value - _tierIndex).clamp(0.0, 1.0);

  /// 0 = III (lowest), 1 = II, 2 = I (highest).
  int get divisionIndex => (tierProgress * 3 + _eps).floor().clamp(0, 2);

  String get divisionLabel => const ['III', 'II', 'I'][divisionIndex];

  String get label => '${tier.label} $divisionLabel';

  /// Progress within the current division, 0..1.
  double get divisionProgress => ((tierProgress * 3) - divisionIndex).clamp(0.0, 1.0);

  @override
  String toString() => label;
}

/// Strength standard for one lift: tier entry thresholds as e1RM ÷ bodyweight.
class StrengthStandard {
  const StrengthStandard({
    required this.id,
    required this.name,
    required this.exerciseIds,
    required this.thresholds,
    required this.targets,
    this.bodyweightLoaded = false,
    this.perHand = false,
  });

  final String id;
  final String name;
  final List<String> exerciseIds;

  /// 7 ascending values: the bodyweight multiple at which each tier (Iron..Champion) starts.
  final List<double> thresholds;
  final MuscleTargets targets;

  /// e1RM includes bodyweight (pull-ups, dips): thresholds are (bodyweight + added) ÷ bodyweight.
  final bool bodyweightLoaded;

  /// Thresholds are per dumbbell.
  final bool perHand;

  /// Champion has no upper threshold; progress runs to 125 % of its entry value.
  static const double championSpan = 0.25;

  factory StrengthStandard.fromJson(Map<String, dynamic> j) {
    Set<MuscleGroup> groups(Object? raw) => {
          for (final g in (raw as List<dynamic>? ?? const [])) ?MuscleGroup.fromName(g as String),
        };
    final primary = groups(j['primary']);
    final secondary = groups(j['secondary'])..removeAll(primary);
    final thresholds = (j['thresholds'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
    if (thresholds.length != Tier.values.length) {
      throw FormatException('Standard ${j['id']} needs ${Tier.values.length} thresholds');
    }
    for (var i = 1; i < thresholds.length; i++) {
      if (thresholds[i] <= thresholds[i - 1]) throw FormatException('Standard ${j['id']} thresholds must ascend');
    }
    return StrengthStandard(
      id: j['id'] as String,
      name: j['name'] as String,
      exerciseIds: (j['exercise_ids'] as List<dynamic>).cast<String>(),
      thresholds: thresholds,
      targets: MuscleTargets(primary: primary, secondary: secondary),
      bodyweightLoaded: j['bodyweight_loaded'] as bool? ?? false,
      perHand: j['per_hand'] as bool? ?? false,
    );
  }

  double _upper(int tierIndex) => tierIndex + 1 < thresholds.length
      ? thresholds[tierIndex + 1]
      : thresholds[tierIndex] * (1 + championSpan);

  RankScore scoreForRatio(double ratio) {
    var i = 0;
    while (i + 1 < thresholds.length && ratio >= thresholds[i + 1]) {
      i++;
    }
    final lo = thresholds[i], hi = _upper(i);
    final f = ((ratio - lo) / (hi - lo)).clamp(0.0, 0.999999);
    return RankScore(i + f);
  }

  /// e1RM (kg) needed for the next division, or null at the very top.
  double? nextThresholdKg(RankScore current, double bodyweight) {
    final t = current.tier.index, d = current.divisionIndex;
    if (t == Tier.values.length - 1 && d == 2) return null;
    final lo = thresholds[t], hi = _upper(t);
    final ratio = d < 2 ? lo + (hi - lo) * (d + 1) / 3 : hi;
    return ratio * bodyweight;
  }
}

class ExerciseRank {
  const ExerciseRank({
    required this.standard,
    required this.bestE1rm,
    required this.ratio,
    required this.score,
    required this.nextThresholdKg,
  });

  final StrengthStandard standard;
  final double bestE1rm;
  final double ratio;
  final RankScore score;
  final double? nextThresholdKg;
}

class GroupContribution {
  const GroupContribution(this.rank, this.weight);
  final ExerciseRank rank;
  final double weight;
}

class GroupRank {
  const GroupRank({required this.group, required this.score, required this.contributions});
  final MuscleGroup group;
  final RankScore score;
  final List<GroupContribution> contributions;
}

class RankSummary {
  const RankSummary({
    required this.exercises,
    required this.groups,
    required this.overall,
    required this.unrankedHints,
  });

  final List<ExerciseRank> exercises;
  final Map<MuscleGroup, GroupRank> groups;
  final RankScore? overall;

  /// For groups without data: standards that would rank them (primary).
  final Map<MuscleGroup, List<StrengthStandard>> unrankedHints;
}

/// Mean of rank scores on the same continuous scale. Identical scores average back to the same rank.
RankScore averageScore(Iterable<RankScore> scores) {
  final list = scores.toList();
  return RankScore(list.fold<double>(0, (a, s) => a + s.value) / list.length);
}

class RankCalculator {
  const RankCalculator(this.standards);

  final List<StrengthStandard> standards;

  static const int windowDays = 90;

  /// [bestE1rmByExercise]: best valid e1RM in the window per exercise id, already including
  /// bodyweight for bodyweight-loaded standards.
  RankSummary compute({required Map<String, double> bestE1rmByExercise, required double bodyweight}) {
    final ranks = <ExerciseRank>[];
    for (final s in standards) {
      double best = 0;
      for (final id in s.exerciseIds) {
        final v = bestE1rmByExercise[id];
        if (v != null && v > best) best = v;
      }
      if (best <= 0 || bodyweight <= 0) continue;
      final ratio = best / bodyweight;
      final score = s.scoreForRatio(ratio);
      ranks.add(ExerciseRank(
        standard: s,
        bestE1rm: best,
        ratio: ratio,
        score: score,
        nextThresholdKg: s.nextThresholdKg(score, bodyweight),
      ));
    }

    final groups = <MuscleGroup, GroupRank>{};
    final hints = <MuscleGroup, List<StrengthStandard>>{};
    for (final g in MuscleGroup.values) {
      final contributions = <GroupContribution>[
        for (final r in ranks)
          if (r.standard.targets.weightFor(g) > 0) GroupContribution(r, r.standard.targets.weightFor(g)),
      ];
      if (contributions.isEmpty) {
        hints[g] = standards.where((s) => s.targets.primary.contains(g)).toList();
        continue;
      }
      final totalW = contributions.fold<double>(0, (a, c) => a + c.weight);
      final value = contributions.fold<double>(0, (a, c) => a + c.rank.score.value * c.weight) / totalW;
      contributions.sort((a, b) => b.weight.compareTo(a.weight));
      groups[g] = GroupRank(group: g, score: RankScore(value), contributions: contributions);
    }

    final overall = groups.isEmpty ? null : averageScore(groups.values.map((g) => g.score));
    return RankSummary(exercises: ranks, groups: groups, overall: overall, unrankedHints: hints);
  }
}
