import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../gamification/presentation/fire_streak.dart';
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

/// Screen 2: the overall body rank first (the full-screen rank-up when its division or tier changed, otherwise its RR bar
/// animating), then each lift one by one. Nothing advances by itself: Continue appears when the animations are done.
class RankStepScreen extends ConsumerStatefulWidget {
  const RankStepScreen({super.key});

  @override
  ConsumerState<RankStepScreen> createState() => _RankStepScreenState();
}

class _RankStepScreenState extends ConsumerState<RankStepScreen> {
  late final SessionSummary? _summary = ref.read(lastSummaryProvider);
  late bool _showRankUp = _summary?.overallRankUp != null;

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final up = summary?.overallRankUp;
    if (_showRankUp && up != null) {
      return RankUpScreen(changes: [up], onDone: () => setState(() => _showRankUp = false));
    }
    final gains = summary?.rankGains ?? const <RankChange>[];
    final overall = gains.where((g) => g.scope == RankChangeScope.overall);
    final lifts = gains.where((g) => g.scope == RankChangeScope.exercise);
    return Stack(children: [
      RankSequenceScreen(
        title: 'RANK PROGRESS',
        // The overall rank leads; after its rank-up screen only the lifts follow.
        gains: [if (up == null) ...overall, ...lifts],
        onDone: () => advanceAfterWorkout(context, summary, AfterStep.rank),
      ),
      const SafeArea(child: Padding(padding: EdgeInsets.only(right: 8), child: AfterSkipButton())),
    ]);
  }
}

/// Screen 3: the streak, a big flame flaring up as the number ticks. Continue appears when the show is over.
class StreakStepScreen extends ConsumerStatefulWidget {
  const StreakStepScreen({super.key});

  @override
  ConsumerState<StreakStepScreen> createState() => _StreakStepScreenState();
}

class _StreakStepScreenState extends ConsumerState<StreakStepScreen> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(lastSummaryProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const AfterSkipButton(),
            const Spacer(),
            Text('STREAK', textAlign: TextAlign.center, style: AppType.displayL.copyWith(letterSpacing: 4, fontSize: 24)),
            const SizedBox(height: 28),
            if (s != null) FireStreak(from: s.streakBefore, to: s.streakAfter, onDone: () => setState(() => _over = true)),
            const Spacer(),
            if (_over)
              BigButton(key: const ValueKey('after-continue'), label: 'Continue', icon: Icons.arrow_forward_rounded, onPressed: () => advanceAfterWorkout(context, s, AfterStep.streak))
            else
              const SizedBox(height: 60),
          ]),
        ),
      ),
    );
  }
}
