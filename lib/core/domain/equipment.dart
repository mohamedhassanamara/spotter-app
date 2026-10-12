/// Loading categories that share a weight increment.
enum EquipmentKind {
  barbell('Barbell'),
  dumbbell('Dumbbell'),
  machineCable('Machine / cable'),
  kettlebell('Kettlebell'),
  bodyweight('Bodyweight (added load)'),
  other('Other');

  const EquipmentKind(this.label);
  final String label;

  /// Maps free-exercise-db equipment strings to a loading category.
  static EquipmentKind fromDataset(String? equipment) {
    switch (equipment?.toLowerCase().trim()) {
      case 'barbell':
      case 'e-z curl bar':
        return EquipmentKind.barbell;
      case 'dumbbell':
        return EquipmentKind.dumbbell;
      case 'machine':
      case 'cable':
        return EquipmentKind.machineCable;
      case 'kettlebells':
        return EquipmentKind.kettlebell;
      case 'body only':
        return EquipmentKind.bodyweight;
      default:
        return EquipmentKind.other;
    }
  }

  static EquipmentKind? fromName(String name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// Weight increments in kg per equipment category. Editable in settings.
class Increments {
  const Increments(this.values);

  final Map<EquipmentKind, double> values;

  static const defaults = Increments({
    EquipmentKind.barbell: 2.5,
    EquipmentKind.dumbbell: 2.0,
    EquipmentKind.machineCable: 2.5,
    EquipmentKind.kettlebell: 4.0,
    EquipmentKind.bodyweight: 2.5,
    EquipmentKind.other: 2.5,
  });

  double of(EquipmentKind kind) => values[kind] ?? defaults.values[kind]!;

  Increments copyWith(EquipmentKind kind, double value) => Increments({...values, kind: value});
}

// Rounding tolerates floating-point noise such as 79.99999.
const double _eps = 1e-6;

double roundToIncrement(double weight, double increment) {
  if (increment <= 0) return weight;
  return _clean((weight / increment).roundToDouble() * increment);
}

double floorToIncrement(double weight, double increment) {
  if (increment <= 0) return weight;
  return _clean(((weight / increment) + _eps).floorToDouble() * increment);
}

double ceilToIncrement(double weight, double increment) {
  if (increment <= 0) return weight;
  return _clean(((weight / increment) - _eps).ceilToDouble() * increment);
}

double _clean(double v) => (v * 1000).roundToDouble() / 1000;

/// The lightest sensible starting load for a calibration session.
double startingWeight(EquipmentKind kind, double increment) {
  switch (kind) {
    case EquipmentKind.barbell:
      return 20.0; // empty Olympic bar
    case EquipmentKind.dumbbell:
      return increment; // lightest dumbbell step
    case EquipmentKind.machineCable:
      return increment * 2;
    case EquipmentKind.kettlebell:
      return 8.0;
    case EquipmentKind.bodyweight:
      return 0.0; // no added load
    case EquipmentKind.other:
      return 0.0;
  }
}
