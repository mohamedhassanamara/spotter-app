import 'dart:convert';
import 'dart:math' as math;

import 'equipment.dart';

/// A machine's or cable's weight stack: the first plate and the step between plates.
class StackSpec {
  const StackSpec({required this.start, required this.step});
  final double start;
  final double step;

  Map<String, Object> toJson() => {'start': start, 'step': step};
  static StackSpec fromJson(Map<String, dynamic> j) => StackSpec(start: (j['start'] as num).toDouble(), step: (j['step'] as num).toDouble());

  @override
  bool operator ==(Object other) => other is StackSpec && other.start == start && other.step == step;

  @override
  int get hashCode => Object.hash(start, step);
}

/// Settings → My gym equipment: the weights that physically exist. Suggestions only ever land on
/// these (plus any weight you've actually logged on that exercise, which exists by definition).
class GymEquipment {
  const GymEquipment({
    this.dumbbells = defaultDumbbells,
    this.smallestPlate = 2.25,
    this.barWeight = 20,
    this.stack = const StackSpec(start: 5, step: 5),
    this.perExercise = const {},
  });

  /// Dumbbell weights available (per hand), ascending.
  final List<double> dumbbells;

  /// Smallest plate, one per side: a barbell moves in steps of 2 × this.
  final double smallestPlate;
  final double barWeight;

  /// Default machine / cable stack.
  final StackSpec stack;

  /// Stack overrides by exercise id (exercise menu → Weight steps).
  final Map<String, StackSpec> perExercise;

  static const List<double> defaultDumbbells = [
    2.5, 5, 7.5, 10, 12.5, 15, 17.5, 20, 22.5, 25, 27.5, 30, 32.5, 35, 37.5, 40, 42.5, 45, 47.5, 50, //
  ];

  static const defaults = GymEquipment();

  double get barbellStep => smallestPlate * 2;

  GymEquipment copyWith({List<double>? dumbbells, double? smallestPlate, StackSpec? stack, Map<String, StackSpec>? perExercise}) => GymEquipment(
        dumbbells: dumbbells ?? this.dumbbells,
        smallestPlate: smallestPlate ?? this.smallestPlate,
        barWeight: barWeight,
        stack: stack ?? this.stack,
        perExercise: perExercise ?? this.perExercise,
      );

  StackSpec stackFor(String exerciseId) => perExercise[exerciseId] ?? stack;

  /// The loads that exist for one exercise. [logged] are weights you've lifted on it (they exist
  /// in your gym even if the settings don't list them, e.g. a 72 kg stack position).
  WeightGrid gridFor({
    required String exerciseId,
    required EquipmentKind kind,
    bool assisted = false,
    Iterable<double> logged = const [],
  }) {
    final values = <double>{};
    void stepped(double start, double step, double top) {
      if (step <= 0) return;
      for (var w = start; w <= top + 1e-9; w += step) {
        values.add(_q(w));
      }
    }

    if (assisted) {
      // Assistance is negative load: 0 and every stack position below it.
      final s = stackFor(exerciseId);
      values.add(0);
      for (var w = s.start; w <= 150; w += s.step) {
        values.add(_q(-w));
      }
    } else {
      switch (kind) {
        case EquipmentKind.dumbbell:
          values.addAll(dumbbells);
        case EquipmentKind.barbell:
          stepped(barWeight, barbellStep, 400);
        case EquipmentKind.machineCable:
          final s = stackFor(exerciseId);
          stepped(s.start, s.step, 300);
        case EquipmentKind.kettlebell:
          values.addAll(const [4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 32, 36, 40, 48]);
        case EquipmentKind.bodyweight:
          values.add(0);
          stepped(2.5, 2.5, 100); // added load: plates / a dumbbell between the legs
        case EquipmentKind.other:
          values.add(0);
          stepped(2.5, 2.5, 300);
      }
    }
    for (final w in logged) {
      values.add(_q(w));
    }
    return WeightGrid(values);
  }

  /// Weights near zero rounding noise (Liftoff's pound conversions) are kept to 0.05 kg.
  static double _q(double w) => (w * 20).roundToDouble() / 20;

  // Settings encoding.
  static const key = 'gym_equipment';

  String encode() => jsonEncode({
        'dumbbells': dumbbells,
        'smallest_plate': smallestPlate,
        'bar': barWeight,
        'stack': stack.toJson(),
        'per_exercise': {for (final e in perExercise.entries) e.key: e.value.toJson()},
      });

  static GymEquipment decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return GymEquipment(
      dumbbells: [for (final d in (j['dumbbells'] as List<dynamic>? ?? defaultDumbbells)) (d as num).toDouble()]..sort(),
      smallestPlate: (j['smallest_plate'] as num?)?.toDouble() ?? 2.25,
      barWeight: (j['bar'] as num?)?.toDouble() ?? 20,
      stack: j['stack'] == null ? const StackSpec(start: 5, step: 5) : StackSpec.fromJson(j['stack'] as Map<String, dynamic>),
      perExercise: {
        for (final e in ((j['per_exercise'] as Map<String, dynamic>?) ?? const {}).entries) e.key: StackSpec.fromJson(e.value as Map<String, dynamic>),
      },
    );
  }

  /// "2.5–50 kg (20)" for the settings row.
  static String describeDumbbells(List<double> d) {
    if (d.isEmpty) return 'none';
    final steps = {for (var i = 1; i < d.length; i++) _q(d[i] - d[i - 1])};
    final range = '${_fmt(d.first)}–${_fmt(d.last)} kg';
    return steps.length == 1 ? '$range, ${_fmt(steps.first)} kg steps' : '$range (${d.length} pairs)';
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  /// Parses "2.5-50/2.5" (range with step) or "2.5, 5, 7.5, 10" (list) into dumbbell weights.
  static List<double>? parseDumbbells(String text) {
    final t = text.trim();
    final range = RegExp(r'^(\d+(?:\.\d+)?)\s*[-–]\s*(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)$').firstMatch(t);
    if (range != null) {
      final a = double.parse(range.group(1)!), b = double.parse(range.group(2)!), s = double.parse(range.group(3)!);
      if (s <= 0 || b < a) return null;
      return [for (var w = a; w <= b + 1e-9; w += s) _q(w)];
    }
    final parts = t.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList();
    final out = <double>[];
    for (final p in parts) {
      final v = double.tryParse(p);
      if (v == null || v <= 0) return null;
      out.add(_q(v));
    }
    return out.isEmpty ? null : (out.toSet().toList()..sort());
  }
}

/// The ordered set of loads that exist for one exercise.
class WeightGrid {
  WeightGrid(Iterable<double> values) : values = (values.toSet().toList()..sort());

  final List<double> values;

  static const double _eps = 0.01;

  bool contains(double w) => values.any((v) => (v - w).abs() < _eps);

  /// Heaviest available load ≤ [w] (the lightest one if [w] is below all).
  double snapDown(double w) {
    double? best;
    for (final v in values) {
      if (v <= w + _eps) best = v;
    }
    return best ?? values.first;
  }

  /// Lightest available load ≥ [w] (the heaviest one if [w] is above all).
  double snapUp(double w) {
    for (final v in values) {
      if (v >= w - _eps) return v;
    }
    return values.last;
  }

  /// Nearest available load; ties go down.
  double snap(double w) {
    final d = snapDown(w), u = snapUp(w);
    return (w - d) <= (u - w) ? d : u;
  }

  /// Next heavier load, or null at the top.
  double? next(double w) {
    for (final v in values) {
      if (v > w + _eps) return v;
    }
    return null;
  }

  /// Next lighter load, or null at the bottom.
  double? previous(double w) {
    double? best;
    for (final v in values) {
      if (v < w - _eps) best = v;
    }
    return best;
  }

  /// Relative jump from [w] to the next load, on the effective load (bodyweight added for
  /// bodyweight-loaded and assisted lifts). Null at the top.
  double? nextJump(double w, {double bodyweight = 0}) {
    final n = next(w);
    if (n == null) return null;
    final base = math.max(1.0, w + bodyweight);
    return (n - w) / base;
  }
}
