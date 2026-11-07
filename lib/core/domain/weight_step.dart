import 'dart:convert';

/// Weight unit for display. Weights and steps are always stored in kg.
enum WeightUnit {
  kg('kg', 1),
  lb('lb', 2.2046226218);

  const WeightUnit(this.label, this.perKg);
  final String label;
  final double perKg;
}

/// THE place that says how far the keypad's − / + moves a weight, by equipment. One editable table.
/// A per-exercise override (long-press on − / +) beats it; see [resolveStep].
const double customExerciseStep = 2.5;

/// Equipment (free-exercise-db strings, lowercase) → default step in kg.
const Map<String, double> defaultStepByEquipment = {
  'barbell': 2.5,
  'e-z curl bar': 2.5,
  'dumbbell': 2.0,
  'machine': 5.0,
  'plate-loaded': 5.0,
  'cable': 2.5,
  'smith': 2.5,
  'kettlebells': 4.0,
  'body only': 2.5,
};

const double fallbackStep = 2.5;

/// The default step for an exercise from its [equipment] string and name (the name tells a Smith machine or a
/// plate-loaded machine apart from a stack machine); [isCustom] exercises get [customExerciseStep].
double defaultStepFor({String? equipment, String name = '', bool isCustom = false}) {
  if (isCustom) return customExerciseStep;
  final n = name.toLowerCase();
  if (n.contains('smith')) return defaultStepByEquipment['smith']!;
  final eq = equipment?.toLowerCase().trim();
  if (eq == 'machine' && (n.contains('plate') || n.contains('hammer strength') || n.contains('leverage') || n.contains('pendulum'))) {
    return defaultStepByEquipment['plate-loaded']!;
  }
  return defaultStepByEquipment[eq] ?? fallbackStep;
}

/// The step in effect: the exercise's own [override] (when positive) else [fallback].
double resolveStep(double? override, double fallback) => override != null && override > 0 ? override : fallback;

/// Steps offered by the long-press picker (kg); "Custom" takes any other positive number.
const List<double> stepPresets = [0.5, 1, 1.25, 2, 2.5, 5, 10];

/// Kills float noise: 0.30000000000000004 → 0.3, 22.499999 → 22.5 (to 0.001).
double cleanWeight(double v) => (v * 1000).roundToDouble() / 1000;

/// "2", "1.25", "0.5": no trailing zeros, at most 2 decimals.
String formatNumber(double v) {
  final c = cleanWeight(v);
  if (c == c.roundToDouble()) return c.toStringAsFixed(0);
  return c.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// A kg value expressed in [unit] (rounded to 0.01 for lb).
double toUnit(double kg, WeightUnit unit) => unit == WeightUnit.kg ? kg : (kg * unit.perKg * 100).roundToDouble() / 100;

/// Keypad button label: "−2", "+1.25" (kg or lb), unit-aware and without trailing zeros.
String stepLabel(double stepKg, int direction, {WeightUnit unit = WeightUnit.kg}) =>
    '${direction < 0 ? '−' : '+'}${formatNumber(toUnit(stepKg, unit))}';

/// [base] moved one [step] up or down, noise-free; never below 0 unless [allowNegative] (assisted lifts), never above [cap].
double stepWeight(double base, int direction, double step, {double? cap, bool allowNegative = false}) {
  var v = cleanWeight(base + direction * step);
  if (!allowNegative && v < 0) v = 0;
  if (direction > 0 && cap != null && v > cap) v = cap;
  return v;
}

/// Per-exercise step overrides as stored in settings (exercise id → kg).
Map<String, double> decodeExerciseSteps(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final e in j.entries) if (e.value is num && (e.value as num) > 0) e.key: (e.value as num).toDouble()};
  } catch (_) {
    return const {};
  }
}

String encodeExerciseSteps(Map<String, double> m) => jsonEncode(m);
