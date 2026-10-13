/// How an exercise is loaded, which decides the weights that exist for it (Settings → My gym equipment).
enum LoadType {
  /// Barbell: plates on both sides of a bar (the bar's own weight is the first load).
  barbell('Barbell'),

  /// Plate-loaded machine loaded symmetrically on both sides (Smith, leg press, hack squat, sled calf
  /// press, plate-loaded presses and rows): a step is a pair of plates.
  plateBothSides('Plate-loaded, both sides'),

  /// Plate-loaded with a single loading horn or sleeve (T-bar row, pendulum squat, landmine): a step is
  /// one plate.
  plateOneSide('Plate-loaded, one side'),

  /// Selectorized stack or cable (pin machines): the stack's own step.
  stack('Stack / cable'),

  dumbbell('Dumbbell'),
  kettlebell('Kettlebell'),
  bodyweight('Bodyweight'),

  /// Assisted machine: assistance is a negative load on a stack.
  assisted('Assisted stack'),
  other('Other');

  const LoadType(this.label);
  final String label;

  static LoadType? fromName(String? n) {
    for (final t in values) {
      if (t.name == n) return t;
    }
    return null;
  }

  /// The types you can pick for one exercise from the logger's menu.
  static const List<LoadType> pickable = [stack, plateOneSide, plateBothSides];
}

final RegExp _oneSide = RegExp(r't[- ]?bar|landmine|pendulum|belt squat', caseSensitive: false);
final RegExp _bothSides = RegExp(
  r'smith|leg press|hack squat|hack calf|\bsled\b|v[- ]squat|plate[- ]loaded|hammer strength|iso[- ]?lateral|leverage',
  caseSensitive: false,
);

/// The load type of an exercise from its name and dataset equipment, with the reason.
/// - one horn: T-bar rows, pendulum squat, landmine and belt squat, whatever the dataset says;
/// - both sides: Smith, leg press, hack squat, sleds, "leverage" (plate-loaded lever) machines;
/// - every other machine or cable is a stack.
/// Wrong for your gym? Override it from the exercise's menu in the logger ("Weight steps…").
({LoadType type, String why}) explainLoad({required String name, required String? equipment, bool assisted = false}) {
  if (assisted) return (type: LoadType.assisted, why: 'assisted machine');
  final one = _oneSide.firstMatch(name);
  if (one != null) return (type: LoadType.plateOneSide, why: 'name: "${one.group(0)}"');
  final eq = equipment?.toLowerCase().trim();
  switch (eq) {
    case 'dumbbell':
      return (type: LoadType.dumbbell, why: 'dumbbell');
    case 'kettlebells':
      return (type: LoadType.kettlebell, why: 'kettlebell');
    case 'barbell':
    case 'e-z curl bar':
      return (type: LoadType.barbell, why: 'barbell');
    case 'body only':
      return (type: LoadType.bodyweight, why: 'bodyweight');
    case 'machine':
      final both = _bothSides.firstMatch(name);
      return both != null
          ? (type: LoadType.plateBothSides, why: 'machine, name: "${both.group(0)}"')
          : (type: LoadType.stack, why: 'machine with no plate-loaded name: assumed pin stack');
    case 'cable':
      return (type: LoadType.stack, why: 'cable');
    default:
      return (type: LoadType.other, why: 'no equipment listed');
  }
}

LoadType classifyLoad({required String name, required String? equipment, bool assisted = false}) =>
    explainLoad(name: name, equipment: equipment, assisted: assisted).type;
