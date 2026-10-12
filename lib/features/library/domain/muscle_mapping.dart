import '../../../core/domain/muscle_group.dart';

/// Single source of truth mapping free-exercise-db muscle names to the 12 ranking groups.
///
/// Dataset muscles without a group (lower back, adductors, neck) are deliberately unmapped;
/// see docs/DECISIONS.md. Abductors count towards glutes (glute medius is the main abductor).
const Map<String, MuscleGroup?> datasetMuscleToGroup = {
  'chest': MuscleGroup.chest,
  'lats': MuscleGroup.back,
  'middle back': MuscleGroup.back,
  'lower back': null,
  'shoulders': MuscleGroup.shoulders,
  'biceps': MuscleGroup.biceps,
  'triceps': MuscleGroup.triceps,
  'forearms': MuscleGroup.forearms,
  'abdominals': MuscleGroup.abs,
  'quadriceps': MuscleGroup.quads,
  'hamstrings': MuscleGroup.hamstrings,
  'glutes': MuscleGroup.glutes,
  'abductors': MuscleGroup.glutes,
  'adductors': null,
  'calves': MuscleGroup.calves,
  'traps': MuscleGroup.traps,
  'neck': null,
};

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

MuscleGroup? groupForDatasetMuscle(String muscle) => datasetMuscleToGroup[muscle.toLowerCase().trim()];

/// Maps an exercise's dataset muscles to ranking groups. A group that is both primary and
/// secondary (e.g. lats primary + middle back secondary) counts as primary only.
MuscleTargets targetsFor(Iterable<String> primaryMuscles, Iterable<String> secondaryMuscles) {
  final primary = <MuscleGroup>{
    for (final m in primaryMuscles) ?groupForDatasetMuscle(m),
  };
  final secondary = <MuscleGroup>{
    for (final m in secondaryMuscles) ?groupForDatasetMuscle(m),
  }..removeAll(primary);
  return MuscleTargets(primary: primary, secondary: secondary);
}
