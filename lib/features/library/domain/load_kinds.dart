/// Exercises whose load is logged relative to bodyweight.
library;

/// Assisted machines/bands: assistance is logged as negative weight, effective load = bodyweight + weight.
const Set<String> assistedExerciseIds = {'sp_assisted_pull_up_machine', 'sp_assisted_dip_machine', 'Band_Assisted_Pull-Up'};

/// Bodyweight exercises whose dataset equipment isn't "body only" (logged as optional added load).
const Set<String> extraBodyweightExerciseIds = {...assistedExerciseIds, 'Hyperextensions_Back_Extensions'};

bool isAssisted(String exerciseId) => assistedExerciseIds.contains(exerciseId);
