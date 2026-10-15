import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../gamification/domain/achievements.dart';
import '../../gamification/domain/stats.dart';
import '../../ranks/domain/ranks.dart';
import '../../workout/data/finish_service.dart';
import '../../workout/presentation/summary_screen.dart';

/// Debug-only: the workout summary with representative demo data.
SessionSummary demoSummary() => SessionSummary(
      sessionId: 0,
      name: 'Push A',
      duration: const Duration(minutes: 64),
      volume: 8640,
      workingSets: 18,
      prs: const [
        PrRecord(sessionId: 0, exerciseId: 'Barbell_Bench_Press_-_Medium_Grip', name: 'Barbell Bench Press', e1rm: 104.5, previous: 101.7),
      ],
      xpSession: 395,
      xpBonus: 140,
      levelBefore: 14,
      levelAfter: 15,
      rankChanges: [
        RankChange(
          name: 'Bench press',
          fromScore: RankScore.of(Tier.emerald, division: 2, lp: 80),
          toScore: RankScore.of(Tier.emerald, division: 1, lp: 4),
          scope: RankChangeScope.exercise,
        ),
        RankChange(
          name: 'Triceps',
          fromScore: RankScore.of(Tier.gold, division: 3, lp: 10),
          toScore: RankScore.of(Tier.gold, division: 4, lp: 92),
          scope: RankChangeScope.muscle,
        ),
      ],
      overrideSets: 1,
      flags: const [],
      achievements: const [
        AchievementDef(key: 'pr_25', title: 'Record Breaker', description: 'Set 25 valid PRs.', icon: 'star', type: AchievementType.prs, threshold: 25),
      ],
      questsCompleted: const ['Hit the top of your rep range on 2 lifts'],
      healthSaved: true,
      disciplinePct: 94.4,
      streakBefore: 178,
      streakAfter: 179,
    );

class SummaryPreviewScreen extends ConsumerStatefulWidget {
  const SummaryPreviewScreen({super.key});

  @override
  ConsumerState<SummaryPreviewScreen> createState() => _SummaryPreviewScreenState();
}

class _SummaryPreviewScreenState extends ConsumerState<SummaryPreviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(lastSummaryProvider.notifier).set(demoSummary()));
  }

  @override
  Widget build(BuildContext context) => const SummaryScreen();
}
