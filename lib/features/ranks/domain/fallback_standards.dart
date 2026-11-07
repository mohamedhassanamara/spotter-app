import '../../library/domain/exercise_info.dart';
import 'ranks.dart';

/// Estimated strength standards for exercises that have no hand-made one in `assets/strength_standards.json`.
///
/// **Every library exercise ranks.** A fallback standard is built from three editable tables on this page:
///
/// (Factors are calibrated against the hand-made standards: dumbbell curl 0.18 = 0.45 × 0.40, cable pushdown 0.42 ≈ 0.50 × 0.80, leg extension 0.9 ≈ 0.80 × 1.05.)
/// 1. [MovementPattern]: which of the five base lifts the exercise relates to (`bases` in strength_standards.json:
///    bench, squat, deadlift, ohp, row) and how heavy a typical *compound* / *isolation* version is compared with it
///    (`compound` / `isolation` factor, the same "typical ratio" idea the hand-made standards use).
/// 2. [equipmentRule]: a multiplier and the standard kind by equipment (a dumbbell is per hand, a cable or machine
///    moves a different load than the barbell, "body only" lifts count bodyweight).
/// 3. [bodyweightAnchors]: the five anchors (× bodyweight, e1RM includes bodyweight) of an unweighted lift.
///
/// anchors = base anchors × pattern factor × equipment multiplier. Such a standard is flagged
/// [StrengthStandard.estimated] and the detail sheet says so. The pattern comes from the user's choice (custom
/// exercises pick one when created) or from the exercise's primary muscle.
enum MovementPattern {
  horizontalPush('Horizontal push (chest)', 'bench', 0.85, 0.35),
  verticalPush('Vertical push (shoulders)', 'ohp', 0.90, 0.50),
  pull('Pull (back)', 'row', 0.90, 0.55),
  squat('Squat / quads', 'squat', 0.85, 0.80),
  hinge('Hinge / hamstrings', 'deadlift', 0.75, 0.55),
  glute('Glutes / hips', 'squat', 1.00, 0.50),
  calf('Calves', 'squat', 1.00, 1.00),
  curl('Curl (biceps)', 'bench', 0.50, 0.45),
  triceps('Triceps', 'bench', 0.55, 0.50),
  forearm('Forearms / grip', 'bench', 0.45, 0.45),
  core('Core', 'bench', 0.55, 0.70),
  traps('Traps / neck', 'deadlift', 0.40, 0.35),
  other('Other', 'bench', 0.50, 0.45);

  const MovementPattern(this.label, this.base, this.compound, this.isolation);
  final String label;

  /// Key in the `bases` table of strength_standards.json.
  final String base;
  final double compound, isolation;

  static MovementPattern? fromName(String? n) {
    for (final p in values) {
      if (p.name == n) return p;
    }
    return null;
  }
}

/// Primary muscle (free-exercise-db) → pattern, used when nobody chose one.
const Map<String, MovementPattern> patternByMuscle = {
  'chest': MovementPattern.horizontalPush,
  'shoulders': MovementPattern.verticalPush,
  'lats': MovementPattern.pull,
  'middle back': MovementPattern.pull,
  'lower back': MovementPattern.hinge,
  'traps': MovementPattern.traps,
  'neck': MovementPattern.traps,
  'biceps': MovementPattern.curl,
  'triceps': MovementPattern.triceps,
  'forearms': MovementPattern.forearm,
  'quadriceps': MovementPattern.squat,
  'hamstrings': MovementPattern.hinge,
  'glutes': MovementPattern.glute,
  'calves': MovementPattern.calf,
  'adductors': MovementPattern.glute,
  'abductors': MovementPattern.glute,
  'abdominals': MovementPattern.core,
};

/// Standard kind, per-hand flag and multiplier by equipment (free-exercise-db strings).
({StandardKind kind, bool perHand, double multiplier}) equipmentRule(String? equipment) => switch (equipment?.toLowerCase().trim()) {
      'barbell' || 'e-z curl bar' => (kind: StandardKind.free, perHand: false, multiplier: 1.0),
      'dumbbell' || 'kettlebells' => (kind: StandardKind.free, perHand: true, multiplier: 0.40),
      'machine' => (kind: StandardKind.machine, perHand: false, multiplier: 1.05),
      'cable' => (kind: StandardKind.cable, perHand: false, multiplier: 0.80),
      'body only' => (kind: StandardKind.bodyweight, perHand: false, multiplier: 1.0),
      _ => (kind: StandardKind.free, perHand: false, multiplier: 0.50), // bands, balls, rollers, unknown
    };

/// Anchors (beginner … elite, × bodyweight) of an unweighted bodyweight lift: upper body (push-ups, pull-ups, dips) and
/// lower body / core (the values of the hand-made crunch, back extension and leg raise standards).
const List<double> bodyweightAnchorsUpper = [1.10, 1.30, 1.50, 1.80, 2.10];
const List<double> bodyweightAnchorsLower = [1.40, 1.60, 1.80, 2.10, 2.40];

const Set<MovementPattern> _upper = {
  MovementPattern.horizontalPush,
  MovementPattern.verticalPush,
  MovementPattern.pull,
  MovementPattern.curl,
  MovementPattern.triceps,
  MovementPattern.forearm,
};

/// The pattern of [info]: [chosen] (a custom exercise's own pick) else its primary muscle, else [MovementPattern.other].
MovementPattern patternFor(ExerciseInfo info, {MovementPattern? chosen}) {
  if (chosen != null) return chosen;
  for (final m in info.primaryMuscles) {
    final p = patternByMuscle[m.toLowerCase()];
    if (p != null) return p;
  }
  return MovementPattern.other;
}

/// The estimated standard for [info]. [bases] is the `bases` table of strength_standards.json (name → five anchors).
StrengthStandard fallbackStandardFor(
  ExerciseInfo info, {
  required Map<String, List<double>> bases,
  MovementPattern? chosen,
  double machineStrictness = 1,
  BodyweightScaling scaling = BodyweightScaling.linear,
}) {
  final pattern = patternFor(info, chosen: chosen);
  final rule = equipmentRule(info.equipment);
  final List<double> anchors;
  if (rule.kind == StandardKind.bodyweight) {
    anchors = _upper.contains(pattern) ? bodyweightAnchorsUpper : bodyweightAnchorsLower;
  } else {
    final factor = (info.isCompound ? pattern.compound : pattern.isolation) * rule.multiplier;
    final base = bases[pattern.base] ?? bases.values.first;
    anchors = [for (final a in base) double.parse((a * factor).toStringAsFixed(4))];
  }
  return StrengthStandard(
    id: 'estimated_${info.id}',
    name: info.name,
    kind: rule.kind,
    exerciseIds: [info.id],
    anchors: anchors,
    perHand: rule.perHand,
    strictness: rule.kind == StandardKind.machine || rule.kind == StandardKind.cable ? machineStrictness : 1,
    scaling: scaling,
    estimated: true,
  );
}

/// [explicit] standards plus an estimated one for every catalog exercise that has none.
List<StrengthStandard> withFallbacks(
  List<StrengthStandard> explicit,
  Iterable<ExerciseInfo> catalog, {
  required Map<String, List<double>> bases,
  Map<String, MovementPattern> chosen = const {},
  double machineStrictness = 1,
  BodyweightScaling scaling = BodyweightScaling.linear,
}) {
  final covered = {for (final s in explicit) ...s.exerciseIds};
  return [
    ...explicit,
    for (final e in catalog)
      if (!covered.contains(e.id))
        fallbackStandardFor(e, bases: bases, chosen: chosen[e.id], machineStrictness: machineStrictness, scaling: scaling),
  ];
}
