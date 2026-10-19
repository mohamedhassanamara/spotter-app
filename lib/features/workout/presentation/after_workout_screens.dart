import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../gamification/presentation/streak_celebration.dart';
import '../../ranks/presentation/rank_sequence_screen.dart';
import '../../ranks/presentation/rank_up_screen.dart';
import '../data/finish_service.dart';
import '../domain/after_workout.dart';

String routeForStep(AfterStep s) => switch (s) {
      AfterStep.congrats => Routes.summary,
      AfterStep.rank => Routes.rankSequence,
      AfterStep.streak => Routes.streak,
    };

/// Goes to the step after [from], or Home after the last one.
void advanceAfterWorkout(BuildContext context, SessionSummary? s, AfterStep from) {
  final next = s == null ? null : stepAfter(s, from);
  if (next == null) {
    context.go(Routes.home);
  } else {
    context.pushReplacement(routeForStep(next));
  }
}

/// "Skip" at the top right of every after-workout screen: straight to Home.
class AfterSkipButton extends StatelessWidget {
  const AfterSkipButton({super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: TextButton(key: const ValueKey('after-skip'), onPressed: () => context.go(Routes.home), child: const Text('Skip')),
      );
}

/// Screen 2: the rank sequence (every lift, muscle, region, then overall), then the full-screen rank-up when the overall rank changed.
class RankStepScreen extends ConsumerStatefulWidget {
  const RankStepScreen({super.key});

  @override
  ConsumerState<RankStepScreen> createState() => _RankStepScreenState();
}

class _RankStepScreenState extends ConsumerState<RankStepScreen> {
  bool _overall = false;

  @override
  Widget build(BuildContext context) {
    final summary = ref.read(lastSummaryProvider);
    void next() => advanceAfterWorkout(context, summary, AfterStep.rank);
    final up = summary?.overallRankUp;
    if (_overall && up != null) return RankUpScreen(changes: [up], onDone: next);
    return Stack(children: [
      RankSequenceScreen(gains: summary?.rankGains ?? const [], onDone: up == null ? next : () => setState(() => _overall = true)),
      const SafeArea(child: Padding(padding: EdgeInsets.only(right: 8), child: AfterSkipButton())),
    ]);
  }
}

/// Screen 3: the streak, ticking up.
class StreakStepScreen extends ConsumerWidget {
  const StreakStepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(lastSummaryProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const AfterSkipButton(),
            const Spacer(),
            Text('STREAK', textAlign: TextAlign.center, style: AppType.displayL.copyWith(letterSpacing: 4, fontSize: 24)),
            const SizedBox(height: 16),
            if (s != null) StreakCelebration(from: s.streakBefore, to: s.streakAfter),
            const Spacer(),
            BigButton(key: const ValueKey('after-continue'), label: 'Done', icon: Icons.check_rounded, onPressed: () => advanceAfterWorkout(context, s, AfterStep.streak)),
          ]),
        ),
      ),
    );
  }
}
