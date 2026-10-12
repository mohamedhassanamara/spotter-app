import 'dart:convert';
import 'dart:math' as math;

import '../../../core/domain/muscles.dart';

/// All dataset muscle names, in a stable display order (used by filters and the custom-exercise form).
const List<String> datasetMuscles = [
  'chest',
  'lats',
  'middle back',
  'lower back',
  'shoulders',
  'traps',
  'biceps',
  'triceps',
  'forearms',
  'abdominals',
  'quadriceps',
  'hamstrings',
  'glutes',
  'calves',
  'abductors',
  'adductors',
  'neck',
];

/// Hand-authored contributions from `assets/exercise_muscles.json` (every exercise in the owner's
/// routines and Liftoff history). Loaded once at startup by `bootstrapDatabase`; exercises not in
/// it derive their contributions from the dataset muscles ([deriveTargets]).
class ExerciseMuscleTable {
  ExerciseMuscleTable._();

  static Map<String, MuscleTargets> _table = const {};

  static bool get isLoaded => _table.isNotEmpty;

  static void load(String json) {
    final raw = (jsonDecode(json) as Map<String, dynamic>)['exercises'] as Map<String, dynamic>;
    _table = {
      for (final e in raw.entries)
        e.key: MuscleTargets({
          for (final w in (e.value as Map<String, dynamic>).entries)
            ?Muscle.fromKey(w.key): (w.value as num).toDouble(),
        }),
    };
  }

  static MuscleTargets? lookup(String exerciseId) => _table[exerciseId];

  static Iterable<String> get ids => _table.keys;
}

/// Contributions for an exercise: the hand-authored table, else derived from its dataset muscles.
MuscleTargets targetsFor(String id, String name, Iterable<String> primaryMuscles, Iterable<String> secondaryMuscles) =>
    ExerciseMuscleTable.lookup(id) ?? deriveTargets(name, primaryMuscles, secondaryMuscles);

/// Default contributions: dataset primary muscles at 1.0 and secondary at 0.3, split into the 20
/// ranking muscles by name keywords (incline → upper chest, decline/dip → lower chest, lateral raise
/// → middle delt, reverse fly/face pull → rear delt, twists and side bends → obliques).
MuscleTargets deriveTargets(String name, Iterable<String> primaryMuscles, Iterable<String> secondaryMuscles) {
  final n = name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);
  final out = <Muscle, double>{};
  void add(Muscle m, double w) => out[m] = math.max(out[m] ?? 0, w);

  void map(String dataset, double w) {
    switch (dataset.toLowerCase().trim()) {
      case 'chest':
        if (has(['incline'])) {
          add(Muscle.upperChest, w);
          add(Muscle.lowerChest, w * 0.5);
        } else if (has(['decline', 'dip'])) {
          add(Muscle.lowerChest, w);
          add(Muscle.upperChest, w * 0.3);
        } else {
          add(Muscle.lowerChest, w);
          add(Muscle.upperChest, w * 0.6);
        }
      case 'shoulders':
        if (has(['reverse fly', 'reverse flye', 'rear delt', 'face pull', 'rear lateral', 'bent over lateral', 'bent-over lateral', 'reverse machine'])) {
          add(Muscle.rearDelt, w);
        } else if (has(['lateral', 'upright row', 'side raise', 'y raise', 'y-raise'])) {
          add(Muscle.middleDelt, w);
        } else if (has(['front raise', 'front cable raise', 'front plate', 'front dumbbell raise', 'front incline'])) {
          add(Muscle.frontDelt, w);
        } else if (has(['row', 'pull', 'chin'])) {
          // Shoulders as a helper in pulling: the rear delts.
          add(Muscle.rearDelt, w);
        } else {
          add(Muscle.frontDelt, w);
          if (has(['press', 'military', 'overhead', 'arnold', 'push press', 'jerk', 'handstand'])) add(Muscle.middleDelt, w * 0.5);
        }
      case 'lats':
        add(Muscle.lats, w);
      case 'middle back':
        add(Muscle.upperBack, w);
      case 'traps':
        add(Muscle.traps, w);
      case 'lower back':
        add(Muscle.lowerBack, w);
      case 'abdominals':
        if (has(['oblique', 'twist', 'side bend', 'woodchop', 'wood chop', 'side plank', 'pallof', 'russian', 'windmill', 'side jackknife'])) {
          add(Muscle.obliques, w);
          add(Muscle.abdominals, w * 0.4);
        } else {
          add(Muscle.abdominals, w);
        }
      case 'biceps':
        add(Muscle.biceps, w);
      case 'triceps':
        add(Muscle.triceps, w);
      case 'forearms':
        add(Muscle.forearms, w);
      case 'quadriceps':
        add(Muscle.quadriceps, w);
      case 'hamstrings':
        add(Muscle.hamstrings, w);
      case 'glutes':
        add(Muscle.glutes, w);
      case 'calves':
        add(Muscle.calves, w);
      case 'abductors':
        add(Muscle.abductors, w);
      case 'adductors':
        add(Muscle.adductors, w);
      case 'neck':
        add(Muscle.traps, w * 0.3);
    }
  }

  for (final m in secondaryMuscles) {
    map(m, 0.3);
  }
  for (final m in primaryMuscles) {
    map(m, 1.0);
  }
  return MuscleTargets(out);
}
