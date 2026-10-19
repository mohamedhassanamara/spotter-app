import '../../../core/domain/training.dart';

/// Praise for a good override (heavier than suggested, still inside the rep range at the prescribed effort), kept to a
/// moderate rate: at most once per exercise per workout and at most twice per workout, in varied words.
class PraisePolicy {
  const PraisePolicy();

  static const int perWorkout = 2;

  static const List<String> messages = [
    'Beat the target and owned it.',
    'Heavier than planned, and every rep clean. Nice.',
    'You went up and held the range. Disciplined.',
    'Extra weight, still on target. Good call.',
    'That one was earned.',
  ];

  /// The message to show after [set] was completed, or null. [praisedExercises] and [given] are what this workout
  /// has already had; [seed] (the session id) shifts the wording from workout to workout.
  String? next({required LoggedSet set, required int exerciseKey, required Set<int> praisedExercises, required int given, int seed = 0}) {
    if (!set.isGoodOverride || given >= perWorkout || praisedExercises.contains(exerciseKey)) return null;
    return messages[(seed.abs() + given) % messages.length];
  }
}
