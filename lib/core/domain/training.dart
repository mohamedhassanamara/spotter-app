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
  String toString() => '$min–$max';

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
  });

  final double weight;
  final int reps;
  final double? rpe;
  final bool isWarmup;
  final bool isOverride;
  final double? suggestedWeight;
  final bool completed;

  bool get isWorking => !isWarmup && completed;

  double get effectiveRpe => rpe ?? defaultRpe;

  /// Override sets at RPE ≥ 9.5 are excluded from ranks and PRs.
  bool get isEgoSet => isOverride && (rpe ?? 0) >= egoRpeThreshold;

  /// Valid for ranks and PRs.
  bool get isValidForRecords => isWorking && !isEgoSet;

  /// e1RM including [bodyweight] for bodyweight-loaded lifts.
  double e1rm({double bodyweight = 0}) => estimateOneRm(weight + bodyweight, reps, rpe);

  /// Whether the set followed the suggestion (within ±5 %).
  bool get followedSuggestion => followsSuggestion(weight, suggestedWeight);
}

/// ±5 % tolerance. A suggestion of 0 kg (bodyweight) is followed only by 0 kg.
bool followsSuggestion(double weight, double? suggested) {
  if (suggested == null) return false;
  if (suggested <= 0) return weight <= 0;
  return (weight - suggested).abs() <= suggested * 0.05 + 1e-9;
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

  List<LoggedSet> get workingSets => sets.where((s) => s.isWorking).toList();

  bool get hasWorkingSets => sets.any((s) => s.isWorking);

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
      if (validOnly && s.isEgoSet) continue;
      final e = s.e1rm(bodyweight: bodyweight);
      if (e > best) best = e;
    }
    return best;
  }

  bool get hasOverrides => workingSets.any((s) => s.isOverride);

  bool get hasEgoOverrides => workingSets.any((s) => s.isEgoSet);

  double get volume => workingSets.fold<double>(0, (v, s) => v + s.weight * s.reps);
}
