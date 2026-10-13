import 'dart:math' as math;

import '../../../core/domain/muscles.dart';

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


/// Strength score 0–1000: 25 per division point, so Iron IV = 0, each division = 25, Master = 700,
/// Grandmaster = 800, Challenger = 900, and 1000 is the cap (Challenger + 4 points).
const double strengthPerPoint = 25;

extension StrengthScore on RankScore {
  int get strength => (value * strengthPerPoint).round().clamp(0, 1000);
}

RankScore scoreFromStrength(num strength) => RankScore(strength / strengthPerPoint);

/// How bodyweight normalises a load. Allometric: scaled = e1RM / (reference × (bodyweight / reference)^exponent).
/// Exponent 1 is the plain e1RM ÷ bodyweight ratio; 0.67 (strength scales with muscle cross-section,
/// i.e. mass^⅔) stops heavier lifters being penalised for not lifting in proportion to bodyweight.
class BodyweightScaling {
  const BodyweightScaling({this.referenceBodyweight = 100, this.exponent = 1});

  final double referenceBodyweight;
  final double exponent;

  static const linear = BodyweightScaling();
  static const allometric = BodyweightScaling(exponent: 0.67);

  /// The load that counts as "1× bodyweight" for a lifter of [bodyweight] kg.
  double normalizer(double bodyweight) =>
      exponent == 1 ? bodyweight : referenceBodyweight * math.pow(bodyweight / referenceBodyweight, exponent);
}

enum StandardKind {
  free,
  machine,
  cable,

  /// e1RM includes bodyweight (assisted machines subtract the assistance).
  bodyweight;

  static StandardKind fromName(String? n) => values.firstWhere((k) => k.name == n, orElse: () => free);
}

/// Strength standard for one or more exercises: tier entry thresholds as e1RM ÷ bodyweight, derived
/// from five anchors (beginner … elite). See assets/strength_standards.json.
class StrengthStandard {
  StrengthStandard({
    required this.id,
    required this.name,
    required this.kind,
    required this.exerciseIds,
    required this.anchors,
    this.perHand = false,
    double strictness = 1,
    this.scaling = BodyweightScaling.linear,
  }) : thresholds = thresholdsFromAnchors([for (final a in anchors) a * strictness]);

  /// Allometric scaling for loaded lifts. Bodyweight lifts always use the plain ratio: their load is
  /// bodyweight itself, so it already scales with the lifter.
  final BodyweightScaling scaling;

  /// The divisor that turns an e1RM into the ratio the thresholds are expressed in.
  double normalizer(double bodyweight) => bodyweightLoaded ? bodyweight : scaling.normalizer(bodyweight);

  double ratioFor(double e1rm, double bodyweight) => bodyweight <= 0 ? 0 : e1rm / normalizer(bodyweight);

  final String id;
  final String name;
  final StandardKind kind;
  final List<String> exerciseIds;

  /// beginner, novice, intermediate, advanced, elite (before machine strictness).
  final List<double> anchors;
  final bool perHand;

  /// 10 ascending values: the bodyweight multiple at which each tier (Iron..Challenger) starts.
  final List<double> thresholds;

  bool get bodyweightLoaded => kind == StandardKind.bodyweight;

  /// Iron 0, Bronze = beginner, Silver = novice, Gold = midpoint novice–intermediate,
  /// Platinum = intermediate, Emerald = midpoint intermediate–advanced, Diamond = advanced,
  /// Master = elite, Grandmaster = elite × 1.15, Challenger = elite × 1.30.
  static List<double> thresholdsFromAnchors(List<double> a) {
    if (a.length != 5) throw const FormatException('A standard needs 5 anchors');
    for (var i = 1; i < 5; i++) {
      if (a[i] <= a[i - 1]) throw const FormatException('Anchors must ascend');
    }
    return [0, a[0], a[1], (a[1] + a[2]) / 2, a[2], (a[2] + a[3]) / 2, a[3], a[4], a[4] * 1.15, a[4] * 1.30];
  }

  factory StrengthStandard.fromJson(Map<String, dynamic> j, {double machineStrictness = 1, BodyweightScaling scaling = BodyweightScaling.linear}) {
    final kind = StandardKind.fromName(j['kind'] as String?);
    final a = j['anchors'] as Map<String, dynamic>;
    return StrengthStandard(
      id: j['id'] as String,
      name: j['name'] as String,
      kind: kind,
      exerciseIds: (j['exercise_ids'] as List<dynamic>).cast<String>(),
      anchors: [for (final k in const ['beginner', 'novice', 'intermediate', 'advanced', 'elite']) (a[k] as num).toDouble()],
      perHand: j['per_hand'] as bool? ?? false,
      strictness: kind == StandardKind.machine || kind == StandardKind.cable ? machineStrictness : 1,
      scaling: scaling,
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

  /// e1RM (kg, bodyweight included for bodyweight lifts) needed for the next division, or null at Challenger.
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
    return ratioForPoints(target) * normalizer(bodyweight);
  }
}

/// Epley is unreliable for long sets: for scoring, reps + reps in reserve count up to 20.
const int scoringRepCap = 20;

/// e1RM used for strength scores: load (plus bodyweight for bodyweight lifts) with reps + RIR capped.
double scoringE1rm({required double load, required int reps, double? rpe}) {
  if (reps <= 0 || load <= 0) return 0;
  final rir = 10 - (rpe ?? 9.0);
  final effective = (reps + rir).clamp(0, scoringRepCap.toDouble());
  return load * (1 + effective / 30);
}

/// Bodyweight over time (Apple Health weigh-ins and manual entries). Between weigh-ins it's linear;
/// before the first or after the last it holds that value. Each set is scored at the bodyweight of
/// its day, as Liftoff does.
class BodyweightTimeline {
  BodyweightTimeline(Iterable<(DateTime, double)> samples) : _s = [...samples]..sort((a, b) => a.$1.compareTo(b.$1));

  final List<(DateTime, double)> _s;

  static final empty = BodyweightTimeline(const []);

  bool get isEmpty => _s.isEmpty;

  double get latest => _s.isEmpty ? 0 : _s.last.$2;

  double at(DateTime t) {
    if (_s.isEmpty) return 0;
    if (!t.isAfter(_s.first.$1)) return _s.first.$2;
    if (!t.isBefore(_s.last.$1)) return _s.last.$2;
    for (var i = 1; i < _s.length; i++) {
      final (t1, w1) = _s[i];
      if (t.isAfter(t1)) continue;
      final (t0, w0) = _s[i - 1];
      final span = t1.difference(t0).inSeconds;
      if (span <= 0) return w1;
      return w0 + (w1 - w0) * t.difference(t0).inSeconds / span;
    }
    return _s.last.$2;
  }
}

/// One exercise's best strength score in the window.
class ExerciseRank {
  const ExerciseRank({
    required this.exerciseId,
    required this.name,
    required this.standard,
    required this.score,
    required this.bestE1rm,
    required this.bodyweight,
    required this.weight,
    required this.reps,
    required this.date,
    required this.targets,
    required this.nextThresholdKg,
  });

  final String exerciseId;
  final String name;
  final StrengthStandard standard;
  final RankScore score;

  /// Scoring e1RM of the best set (bodyweight included for bodyweight lifts).
  final double bestE1rm;

  /// Bodyweight on the day of the best set.
  final double bodyweight;
  final double weight;
  final int reps;
  final DateTime date;
  final MuscleTargets targets;

  /// e1RM for the next division at today's bodyweight, or null at Challenger.
  final double? nextThresholdKg;

  double get ratio => bodyweight <= 0 ? 0 : bestE1rm / bodyweight;

  /// The ratio the standard scores (allometric for loaded lifts).
  double get scaledRatio => standard.ratioFor(bestE1rm, bodyweight);
  int get strength => score.strength;
}

class MuscleContribution {
  const MuscleContribution(this.rank, this.weight);
  final ExerciseRank rank;
  final double weight;
}

class MuscleRank {
  const MuscleRank({required this.muscle, required this.score, required this.contributions});
  final Muscle muscle;
  final RankScore score;

  /// Strongest contribution first.
  final List<MuscleContribution> contributions;
}

class RegionRank {
  const RegionRank({required this.region, required this.score, required this.ranked, required this.total});
  final BodyRegion region;
  final RankScore? score;
  final int ranked;
  final int total;
}

/// The cheapest single-lift improvement that moves a muscle to its next division.
class MuscleNextStep {
  const MuscleNextStep({required this.rank, required this.kg, required this.targetE1rm, required this.nextLabel});
  final ExerciseRank rank;

  /// e1RM increase needed, in kg.
  final double kg;
  final double targetE1rm;
  final String nextLabel;
}

/// For each contributing lift: the e1RM it needs (others unchanged) for the muscle's weighted average
/// to reach the next division. Returns the smallest increase, or null at Challenger.
MuscleNextStep? muscleNextStep(MuscleRank m) {
  final label = m.score.nextLabel;
  if (label == null) return null;
  final target = switch (m.score.tier) {
    Tier.master => RankScore.grandmasterPoints,
    Tier.grandmaster => RankScore.challengerPoints,
    _ => (m.score.value + 1e-9).floorToDouble() + 1,
  };
  final totalW = m.contributions.fold<double>(0, (a, c) => a + c.weight);
  MuscleNextStep? best;
  for (final c in m.contributions) {
    final r = c.rank;
    if (r.bodyweight <= 0) continue;
    final needPoints = r.score.value + (target - m.score.value) * totalW / c.weight;
    final targetE1rm = r.standard.ratioForPoints(needPoints) * r.standard.normalizer(r.bodyweight);
    final kg = targetE1rm - r.bestE1rm;
    if (best == null || kg < best.kg) best = MuscleNextStep(rank: r, kg: kg, targetE1rm: targetE1rm, nextLabel: label);
  }
  return best;
}

/// An exercise that would rank an unranked muscle.
class RankHint {
  const RankHint({required this.exerciseId, required this.name, required this.mine});
  final String exerciseId;
  final String name;

  /// In my routines or history (otherwise a library suggestion).
  final bool mine;
}

class RankSummary {
  const RankSummary({
    required this.exercises,
    required this.muscles,
    required this.regions,
    required this.overall,
    required this.unrankedHints,
    this.hidden = const [],
  });

  final List<ExerciseRank> exercises;
  final Map<Muscle, MuscleRank> muscles;
  final Map<BodyRegion, RegionRank> regions;
  final RankScore? overall;
  final Map<Muscle, List<RankHint>> unrankedHints;

  /// Exercises switched off with "Counts toward rank": scored as usual so their rows can still show
  /// (switch off), but they never feed a muscle, region or overall rank.
  final List<ExerciseRank> hidden;

  static const empty = RankSummary(exercises: [], muscles: {}, regions: {}, overall: null, unrankedHints: {});

  int get rankedRegions => regions.values.where((r) => r.score != null).length;
}

/// Mean of rank scores on the same continuous scale. Identical scores average back to the same rank.
RankScore averageScore(Iterable<RankScore> scores) {
  final list = scores.toList();
  return RankScore(list.fold<double>(0, (a, s) => a + s.value) / list.length);
}

/// Muscle rank: weighted average (by contribution) of the best scores of the exercises training it.
/// Region rank: mean of its ranked muscles. Overall: mean of the ranked regions.
class RankCalculator {
  RankCalculator(this.standards) : _byExercise = {for (final s in standards) for (final id in s.exerciseIds) id: s};

  final List<StrengthStandard> standards;
  final Map<String, StrengthStandard> _byExercise;

  static const int windowDays = 90;

  StrengthStandard? standardFor(String exerciseId) => _byExercise[exerciseId];

  /// Points for one set, or null when the exercise has no standard or no bodyweight is known.
  RankScore? scoreSet({required String exerciseId, required LoggedSetLike set, required double bodyweight}) {
    final s = _byExercise[exerciseId];
    if (s == null || bodyweight <= 0) return null;
    final load = set.weight + (s.bodyweightLoaded ? bodyweight : 0);
    final e = scoringE1rm(load: load, reps: set.reps, rpe: set.rpe);
    if (e <= 0) return null;
    return s.scoreForRatio(s.ratioFor(e, bodyweight));
  }

  RankSummary compute({
    required List<RankedSet> sets,
    required Map<String, MuscleTargets> targets,
    required double currentBodyweight,
    Set<String> excluded = const {},
    Map<String, String> hintNames = const {},
  }) {
    final best = <String, ExerciseRank>{};
    for (final x in sets) {
      final s = _byExercise[x.exerciseId];
      final score = scoreSet(exerciseId: x.exerciseId, set: x, bodyweight: x.bodyweight);
      if (s == null || score == null) continue;
      final cur = best[x.exerciseId];
      if (cur != null && cur.score.value >= score.value) continue;
      best[x.exerciseId] = ExerciseRank(
        exerciseId: x.exerciseId,
        name: x.name,
        standard: s,
        score: score,
        bestE1rm: scoringE1rm(load: x.weight + (s.bodyweightLoaded ? x.bodyweight : 0), reps: x.reps, rpe: x.rpe),
        bodyweight: x.bodyweight,
        weight: x.weight,
        reps: x.reps,
        date: x.date,
        targets: targets[x.exerciseId] ?? MuscleTargets.empty,
        nextThresholdKg: s.nextThresholdKg(score, currentBodyweight > 0 ? currentBodyweight : x.bodyweight),
      );
    }
    final ranks = [for (final r in best.values) if (!excluded.contains(r.exerciseId)) r];
    final hidden = [for (final r in best.values) if (excluded.contains(r.exerciseId)) r];

    final muscles = <Muscle, MuscleRank>{};
    final hints = <Muscle, List<RankHint>>{};
    for (final m in Muscle.values) {
      final contributions = [
        for (final r in ranks)
          if (r.targets.weightFor(m) > 0) MuscleContribution(r, r.targets.weightFor(m)),
      ]..sort((a, b) => b.weight.compareTo(a.weight));
      if (contributions.isEmpty) {
        hints[m] = [
          for (final e in hintNames.entries)
            if (!excluded.contains(e.key) && (targets[e.key]?.weightFor(m) ?? 0) >= MuscleTargets.primaryThreshold && _byExercise.containsKey(e.key))
              RankHint(exerciseId: e.key, name: e.value, mine: true),
        ];
        continue;
      }
      final totalW = contributions.fold<double>(0, (a, c) => a + c.weight);
      final value = contributions.fold<double>(0, (a, c) => a + c.rank.score.value * c.weight) / totalW;
      muscles[m] = MuscleRank(muscle: m, score: RankScore(value), contributions: contributions);
    }

    final regions = <BodyRegion, RegionRank>{};
    for (final r in BodyRegion.values) {
      final ranked = [for (final m in r.muscles) ?muscles[m]?.score];
      regions[r] = RegionRank(
        region: r,
        score: ranked.isEmpty ? null : averageScore(ranked),
        ranked: ranked.length,
        total: r.muscles.length,
      );
    }
    final rankedRegions = [for (final r in regions.values) ?r.score];
    return RankSummary(
      exercises: ranks,
      muscles: muscles,
      regions: regions,
      overall: rankedRegions.isEmpty ? null : averageScore(rankedRegions),
      unrankedHints: hints,
      hidden: hidden,
    );
  }
}

/// The parts of a logged set the scorer needs.
abstract interface class LoggedSetLike {
  double get weight;
  int get reps;
  double? get rpe;
}

/// A valid working set in the ranking window, with the bodyweight of its day.
class RankedSet implements LoggedSetLike {
  const RankedSet({
    required this.exerciseId,
    required this.name,
    required this.weight,
    required this.reps,
    required this.rpe,
    required this.date,
    required this.bodyweight,
  });

  final String exerciseId;
  final String name;
  @override
  final double weight;
  @override
  final int reps;
  @override
  final double? rpe;
  final DateTime date;
  final double bodyweight;
}
