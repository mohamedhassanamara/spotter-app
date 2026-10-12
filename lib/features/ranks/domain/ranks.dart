import '../../../core/domain/muscle_group.dart';

/// League-style ladder: 7 divisional tiers (IV → I) and 3 apex tiers without divisions.
enum Tier {
  iron('Iron'),
  bronze('Bronze'),
  silver('Silver'),
  gold('Gold'),
  platinum('Platinum'),
  emerald('Emerald'),
  diamond('Diamond'),
  master('Master'),
  grandmaster('Grandmaster'),
  challenger('Challenger');

  const Tier(this.label);
  final String label;

  bool get isApex => index >= Tier.master.index;

  static const int divisionalTiers = 7;
  static const int divisionsPerTier = 4;
}

/// A position on the ladder as a continuous number of **points**: one point per division.
///
/// - Divisional tiers: tier i spans points [4i, 4i + 4); division IV = 4i, …, I = 4i + 3.
/// - Master starts at 28, Grandmaster at 32, Challenger at 36 (uncapped).
///
/// Groups and the overall rank average points directly, so the mean of identical ranks maps back
/// to exactly that rank.
class RankScore {
  RankScore(double value) : value = value < 0 ? 0 : value;

  /// Builds the score for a given tier, division (4 = IV … 1 = I) and LP (0–100) — mainly for tests.
  factory RankScore.of(Tier tier, {int division = 4, double lp = 0}) {
    if (tier.isApex) return RankScore(masterPoints + (tier.index - Tier.master.index) * 4 + lp / 100);
    return RankScore(tier.index * 4.0 + (4 - division) + lp / 100);
  }

  final double value;

  static const double masterPoints = 28;
  static const double grandmasterPoints = 32;
  static const double challengerPoints = 36;

  // Floors use a small epsilon so a score on a boundary (or an average of identical scores that
  // lost an ulp) never drops into the previous division.
  static const double _eps = 1e-9;

  int get _point => (value + _eps).floor();

  Tier get tier {
    if (value + _eps >= challengerPoints) return Tier.challenger;
    if (value + _eps >= grandmasterPoints) return Tier.grandmaster;
    if (value + _eps >= masterPoints) return Tier.master;
    return Tier.values[(_point ~/ 4).clamp(0, Tier.divisionalTiers - 1)];
  }

  bool get isApex => tier.isApex;

  /// 0 = IV (lowest) … 3 = I (highest); −1 for apex tiers.
  int get divisionIndex => isApex ? -1 : _point % 4;

  /// "IV".."I", empty for apex tiers.
  String get divisionLabel => isApex ? '' : const ['IV', 'III', 'II', 'I'][divisionIndex];

  String get label => isApex ? tier.label : '${tier.label} $divisionLabel';

  /// League points: 0–100 within a division; for apex tiers, LP above the Master threshold (uncapped).
  int get lp {
    if (isApex) return ((value - masterPoints) * 100 + _eps).floor();
    return (((value - _point) * 100) + _eps).floor().clamp(0, 99);
  }

  /// 0..1 progress to the next division (apex: to the next apex tier; Challenger: per 100 LP).
  double get divisionProgress {
    switch (tier) {
      case Tier.master:
        return ((value - masterPoints) / 4).clamp(0.0, 1.0);
      case Tier.grandmaster:
        return ((value - grandmasterPoints) / 4).clamp(0.0, 1.0);
      case Tier.challenger:
        return ((value - challengerPoints) % 1).clamp(0.0, 1.0);
      default:
        return (value - _point).clamp(0.0, 1.0);
    }
  }

  /// Label of the next step up, or null at Challenger.
  String? get nextLabel {
    switch (tier) {
      case Tier.challenger:
        return null;
      case Tier.grandmaster:
        return Tier.challenger.label;
      case Tier.master:
        return Tier.grandmaster.label;
      default:
        if (divisionIndex < 3) return '${tier.label} ${const ['IV', 'III', 'II', 'I'][divisionIndex + 1]}';
        return tier == Tier.diamond ? Tier.master.label : '${Tier.values[tier.index + 1].label} IV';
    }
  }

  /// "Gold II · 42 LP", "Master · 135 LP".
  String get labelWithLp => '$label · $lp LP';

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

  /// 10 ascending values: the bodyweight multiple at which each tier (Iron..Challenger) starts.
  final List<double> thresholds;
  final MuscleTargets targets;

  /// e1RM includes bodyweight (pull-ups, dips): thresholds are (bodyweight + added) ÷ bodyweight.
  final bool bodyweightLoaded;

  /// Thresholds are per dumbbell.
  final bool perHand;

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

  double get _master => thresholds[Tier.master.index];
  double get _grandmaster => thresholds[Tier.grandmaster.index];
  double get _challenger => thresholds[Tier.challenger.index];

  /// Linear in ratio within every division; apex tiers are linear between their entry ratios and
  /// Challenger continues with the Grandmaster slope (uncapped).
  RankScore scoreForRatio(double ratio) {
    if (ratio >= _challenger) {
      return RankScore(RankScore.challengerPoints + (ratio - _challenger) / (_challenger - _grandmaster) * 4);
    }
    if (ratio >= _grandmaster) {
      return RankScore(RankScore.grandmasterPoints + (ratio - _grandmaster) / (_challenger - _grandmaster) * 4);
    }
    if (ratio >= _master) {
      return RankScore(RankScore.masterPoints + (ratio - _master) / (_grandmaster - _master) * 4);
    }
    var i = 0;
    while (i + 1 < Tier.divisionalTiers && ratio >= thresholds[i + 1]) {
      i++;
    }
    final lo = thresholds[i], hi = thresholds[i + 1];
    final f = ((ratio - lo) / (hi - lo)).clamp(0.0, 1.0);
    return RankScore(i * 4 + f * 4);
  }

  /// Bodyweight multiple at which a point value is reached (inverse of [scoreForRatio]).
  double ratioForPoints(double points) {
    if (points >= RankScore.grandmasterPoints) {
      return _grandmaster + (points - RankScore.grandmasterPoints) / 4 * (_challenger - _grandmaster);
    }
    if (points >= RankScore.masterPoints) {
      return _master + (points - RankScore.masterPoints) / 4 * (_grandmaster - _master);
    }
    final i = (points ~/ 4).clamp(0, Tier.divisionalTiers - 1);
    final f = (points - i * 4) / 4;
    return thresholds[i] + f * (thresholds[i + 1] - thresholds[i]);
  }

  /// e1RM (kg) needed for the next division (or next apex tier), or null at Challenger.
  double? nextThresholdKg(RankScore current, double bodyweight) {
    final double target;
    switch (current.tier) {
      case Tier.challenger:
        return null;
      case Tier.grandmaster:
        target = RankScore.challengerPoints;
      case Tier.master:
        target = RankScore.grandmasterPoints;
      default:
        target = (current.value + 1e-9).floorToDouble() + 1;
    }
    return ratioForPoints(target) * bodyweight;
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

/// The cheapest single-lift improvement that moves a group to its next division.
class GroupNextStep {
  const GroupNextStep({required this.standard, required this.kg, required this.targetE1rm, required this.nextLabel});
  final StrengthStandard standard;

  /// e1RM increase needed on [standard], in kg.
  final double kg;
  final double targetE1rm;
  final String nextLabel;
}

/// For each contributing lift: the e1RM it needs (others unchanged) for the group's weighted average
/// to reach the next division's points. Returns the smallest increase, or null at Challenger.
GroupNextStep? groupNextStep(GroupRank g) {
  final label = g.score.nextLabel;
  if (label == null) return null;
  final target = switch (g.score.tier) {
    Tier.master => RankScore.grandmasterPoints,
    Tier.grandmaster => RankScore.challengerPoints,
    _ => (g.score.value + 1e-9).floorToDouble() + 1,
  };
  final totalW = g.contributions.fold<double>(0, (a, c) => a + c.weight);
  GroupNextStep? best;
  for (final c in g.contributions) {
    final r = c.rank;
    if (r.ratio <= 0) continue;
    final bodyweight = r.bestE1rm / r.ratio;
    final needPoints = r.score.value + (target - g.score.value) * totalW / c.weight;
    final targetE1rm = r.standard.ratioForPoints(needPoints) * bodyweight;
    final kg = targetE1rm - r.bestE1rm;
    if (best == null || kg < best.kg) {
      best = GroupNextStep(standard: r.standard, kg: kg, targetE1rm: targetE1rm, nextLabel: label);
    }
  }
  return best;
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
