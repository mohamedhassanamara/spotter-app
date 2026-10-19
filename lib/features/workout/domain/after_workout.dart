import '../data/finish_service.dart';

/// The screens after Finish, in order: Congratulations always, Rank when a rank moved, Streak when today's workout grew the streak.
enum AfterStep { congrats, rank, streak }

List<AfterStep> afterWorkoutSteps(SessionSummary s) => [
      AfterStep.congrats,
      if (s.rankGains.isNotEmpty || s.overallRankUp != null) AfterStep.rank,
      if (s.streakGrew) AfterStep.streak,
    ];

/// The step after [step], or null when it was the last (then Home).
AfterStep? stepAfter(SessionSummary s, AfterStep step) {
  final steps = afterWorkoutSteps(s);
  final i = steps.indexOf(step);
  return i < 0 || i + 1 >= steps.length ? null : steps[i + 1];
}
