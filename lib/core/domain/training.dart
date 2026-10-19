/// Pure training models shared by the coach, ranks and gamification logic.
library;

/// RPE assumed when the lifter didn't log one.
const double defaultRpe = 9.0;

/// RPE at or above which an override set counts as an ego set.
const double egoRpeThreshold = 9.5;

/// Estimated 1RM: Epley on effective reps, `weight × (1 + (reps + RIR) / 30)` with RIR = 10 − RPE.
double estimateOneRm(double weight, int reps, double? rpe) {
  if (reps <= 0 || weight <= 0) return 0;
  final rir = 10 - (rpe ?? defaultRpe);
  return weight * (1 + (reps + rir) / 30);
}

class RepRange {
  const RepRange(this.min, this.max) : assert(min <= max);
  final int min;
  final int max;

  static const compound = RepRange(6, 10);
  static const isolation = RepRange(10, 15);

  @override
  String toString() => min == max ? '$min' : '$min–$max';

  @override
  bool operator ==(Object other) => other is RepRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// One logged set. Weight is the external load in kg (added load for bodyweight lifts).
class LoggedSet {
  const LoggedSet({
    required this.weight,
    required this.reps,
    this.rpe,
    this.isWarmup = false,
    this.isOverride = false,
    this.suggestedWeight,
    this.completed = true,
    this.isDrop = false,
    this.isMyo = false,
    this.isHold = false,
    this.partials = false,
    this.targetMin,
    this.targetMax,
    this.targetRir,
  });

  final double weight;
  final int reps;
  final double? rpe;
  final bool isWarmup;
  final bool isOverride;
  final double? suggestedWeight;
  final bool completed;

  /// A drop set: counts for volume, never for e1RM, ranks, PRs or progression.
  final bool isDrop;

  /// A myo-rep cycle after the last set: counts for volume like a drop set.
  final bool isMyo;

  /// A weighted static hold; [reps] holds the seconds, so it adds no volume.
  final bool isHold;

  /// "+ partials" (section 7): partial reps after the last full rep. Informational; reps are full reps.
  final bool partials;

  /// Drop, myo or hold: a technique follow-up, never a working set for e1RM, ranks, PRs or progression.
  bool get isFollowUp => isDrop || isMyo || isHold;

  /// weight × reps (0 for a static hold).
  double get tonnage => isHold ? 0 : weight * reps;

  /// The prescribed rep range of this set, when known.
  final int? targetMin;
  final int? targetMax;

  /// Reps in reserve prescribed for this set (0 = to failure), when known.
  final int? targetRir;

  /// Completed, not a warm-up (drop sets included: they count for volume).
  bool get isWorking => !isWarmup && completed;

  double get effectiveRpe => rpe ?? defaultRpe;

  bool get belowRange => targetMin != null && reps < targetMin!;

  /// Ego lifting (section 7): load above the suggestion *and* reps below the bottom of the range,
  /// i.e. it was too heavy. Going to failure inside the range is never ego lifting.
  bool get isEgoSet => isOverride && belowRange;

  /// A good override: heavier than the suggestion (more than 5 %) and still inside the rep range (or above it) at the
  /// prescribed effort. It counts as disciplined, progression accepts the weight, and it is never an ego flag.
  bool get isGoodOverride =>
      isOverride && isWorking && !isFollowUp && targetMin != null && !belowRange && (rpe == null || targetRir == null || rpe! <= 10 - targetRir! + 1e-9);

  /// Valid for ranks and PRs: a completed working set that isn't a drop set or an ego set.
  bool get isValidForRecords => isWorking && !isFollowUp && !isEgoSet;

  /// e1RM including [bodyweight] for bodyweight-loaded lifts.
  double e1rm({double bodyweight = 0}) => estimateOneRm(weight + bodyweight, reps, rpe);

  /// Discipline: load within ±5 % of the suggestion and reps inside the prescribed range, or a good override.
  bool get isDisciplined => followedSuggestion || isGoodOverride;

  /// Within ±5 % of the suggestion and reps inside the prescribed range.
  bool get followedSuggestion =>
      followsSuggestion(weight, suggestedWeight) && !belowRange && (targetMax == null || reps <= targetMax!);
}

/// ±5 % tolerance. A suggestion of 0 kg (bodyweight) is followed only by 0 kg.
bool followsSuggestion(double weight, double? suggested) {
  if (suggested == null) return false;
  if (suggested <= 0) return weight <= 0;
  return (weight - suggested).abs() <= suggested * 0.05 + 1e-9;
}

/// The one-tap effort selector (section 7). Stored as RPE; never shown as RPE.
enum Effort {
  failure('F', 10),
  oneLeft('1', 9),
  twoLeft('2', 8),
  threePlus('3+', 7);

  const Effort(this.label, this.rpe);
  final String label;
  final double rpe;

  Effort get next => values[(index + 1) % values.length];

  /// From a prescribed RIR (0 = failure).
  static Effort fromRir(int? rir) => switch (rir) {
        null => twoLeft,
        <= 0 => failure,
        1 => oneLeft,
        2 => twoLeft,
        _ => threePlus,
      };

  static Effort? fromRpe(double? rpe) {
    if (rpe == null) return null;
    if (rpe >= 9.75) return failure;
    if (rpe >= 8.75) return oneLeft;
    if (rpe >= 7.75) return twoLeft;
    return threePlus;
  }
}

/// How the coach framed a session for one exercise; stored with each session exercise.
enum SuggestionKind {
  calibration,
  seeded,
  increase,
  addReps,
  reduce,
  plateauDeload,
  egoFreeze,
  none;

  /// Sessions where the load was deliberately reduced (used by the "Comeback" achievement).
  bool get isDeload => this == reduce || this == plateauDeload || this == egoFreeze;

  static SuggestionKind fromName(String? name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return none;
  }
}

/// All sets of one exercise within one finished session.
class ExerciseSessionLog {
  const ExerciseSessionLog({
    required this.sessionId,
    required this.date,
    required this.sets,
    this.suggestionKind = SuggestionKind.none,
    this.techniqueDay = false,
  });

  final int sessionId;
  final DateTime date;
  final List<LoggedSet> sets;
  final SuggestionKind suggestionKind;

  /// The coach cut load for low readiness (Red). Such sessions aren't used as the progression base.
  final bool techniqueDay;

  /// Working sets for progression and e1RM: completed, not warm-ups, not drop sets.
  List<LoggedSet> get workingSets => sets.where((s) => s.isWorking && !s.isFollowUp).toList();

  bool get hasWorkingSets => sets.any((s) => s.isWorking && !s.isFollowUp);

  /// Heaviest working weight of the session.
  /// Heaviest working weight (may be negative for assisted lifts); 0 without working sets.
  double get topWeight {
    final w = workingSets;
    if (w.isEmpty) return 0;
    return w.map((s) => s.weight).reduce((a, b) => a > b ? a : b);
  }

  List<LoggedSet> get topSets => workingSets.where((s) => s.weight == topWeight).toList();

  double bestE1rm({double bodyweight = 0, bool validOnly = false}) {
    var best = 0.0;
    for (final s in workingSets) {
      if (validOnly && !s.isValidForRecords) continue;
      final e = s.e1rm(bodyweight: bodyweight);
      if (e > best) best = e;
    }
    return best;
  }

  bool get hasOverrides => workingSets.any((s) => s.isOverride);

  /// Overrides that were not good ones (reps fell below the range, or beyond the prescribed effort).
  bool get hasBadOverrides => workingSets.any((s) => s.isOverride && !s.isGoodOverride);

  bool get hasEgoOverrides => workingSets.any((s) => s.isEgoSet);

  /// Drop sets and myo cycles included; static holds add none.
  double get volume => sets.where((s) => s.isWorking).fold<double>(0, (v, s) => v + s.tonnage);
}
