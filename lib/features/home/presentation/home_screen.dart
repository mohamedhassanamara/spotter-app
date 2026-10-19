import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/domain/dates.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../gamification/domain/streaks.dart';
import '../../ranks/presentation/progress_screen.dart' show enterBodyweight;
import '../../ranks/presentation/rank_badge.dart';
import '../../readiness/presentation/readiness_card.dart';
import '../../recovery/presentation/recovery_card.dart';
import '../../workout/presentation/workout_actions.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bodyweight = ref.watch(latestBodyWeightProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEEE').format(now).toUpperCase(), style: AppType.label.copyWith(color: AppColors.textSecondary)),
          Text(DateFormat('d MMMM').format(now), style: AppType.titleL),
        ]),
        actions: [
          IconButton(
            tooltip: 'Settings',
            iconSize: 26,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(healthSyncProvider.notifier).sync(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            const _HeroCard(),
            const SizedBox(height: 12),
            const ReadinessCard(),
            const SizedBox(height: 12),
            const RecoveryCard(),
            if (bodyweight.hasValue && bodyweight.value == null) ...[
              const SizedBox(height: 12),
              GameCard(
                accent: AppColors.warning,
                onTap: () => enterBodyweight(context, ref),
                child: const Row(children: [
                  Icon(Icons.monitor_weight_outlined, color: AppColors.warning),
                  SizedBox(width: 12),
                  Expanded(child: Text('No bodyweight in Apple Health. Tap to enter it so your lifts can be ranked.')),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            const _PrimaryAction(),
            const _EgoFlags(),
            const _Quests(),
            const _Streak(),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends ConsumerWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranks = ref.watch(ranksProvider);
    final level = ref.watch(levelProvider);
    final overall = ranks.value?.overall;
    final color = overall == null ? AppColors.unranked : tierColors[overall.tier.index];
    if (ranks.isLoading && !ranks.hasValue) return const Skeleton(height: 190, radius: Radii.card);
    return GameCard(
      accent: color,
      glow: overall != null,
      onTap: () => context.go(Routes.progress),
      child: Column(
        children: [
          Row(
            children: [
              RankBadge(score: overall, size: BadgeSize.medium, width: 92),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OVERALL RANK', style: AppType.label.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      overall?.label ?? 'Unranked',
                      style: AppType.displayL.copyWith(fontSize: 28, color: overall == null ? AppColors.textSecondary : color),
                    ),
                    const SizedBox(height: 10),
                    if (overall != null)
                      LpBar(progress: overall.divisionProgress, color: color, lp: overall.lp)
                    else
                      const Text('Log a ranked lift to place on the ladder.', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider()),
          Row(
            children: [
              ProgressRing(
                value: level.progress,
                color: AppColors.xp,
                size: 52,
                stroke: 6,
                child: Text('${level.level}', style: AppType.number.copyWith(fontSize: 18)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Level ${level.level}', style: AppType.title),
                  Text(
                    '${level.xpIntoLevel} / ${level.xpForNext} XP to level ${level.level + 1}',
                    style: AppType.bodyS.copyWith(color: AppColors.textSecondary, fontFeatures: AppType.tabular),
                  ),
                ]),
              ),
              Text('${level.totalXp} XP',
                  style: AppType.bodyS.copyWith(fontFamily: AppType.display, color: AppColors.xp, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One primary button: Resume, or Start the next routine.
class _PrimaryAction extends ConsumerWidget {
  const _PrimaryAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider).value;
    if (active != null) {
      return BigButton(
        label: 'Resume ${active.session.name}',
        icon: Icons.play_arrow_rounded,
        onPressed: () => context.push(Routes.workout),
      );
    }
    final routines = ref.watch(routinesProvider).value ?? const [];
    final history = ref.watch(historyProvider).value;
    final catalog = ref.watch(catalogProvider).value ?? const {};
    final lastRoutineId = history?.sessions.reversed.where((s) => s.routineId != null).firstOrNull?.routineId;
    final next = nextRoutine(routines, lastRoutineId);
    if (next == null) {
      return BigButton(label: 'Create your first routine', icon: Icons.add_rounded, onPressed: () => context.go(Routes.train));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BigButton(
          label: 'Start ${next.routine.name}',
          icon: Icons.play_arrow_rounded,
          onPressed: next.exercises.isEmpty ? null : () => startWorkout(context, ref, routine: next),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                next.exercises.map((e) => e.displayName ?? catalog[e.exerciseId]?.name ?? e.exerciseId).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
              ),
            ),
            TextButton(onPressed: () => context.go(Routes.train), child: const Text('Other')),
          ],
        ),
      ],
    );
  }
}

class _EgoFlags extends ConsumerWidget {
  const _EgoFlags();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freezes = ref.watch(activeFreezesProvider);
    if (freezes.isEmpty) return const SizedBox.shrink();
    final catalog = ref.watch(catalogProvider).value ?? const {};
    final now = ref.watch(clockProvider)();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Ego flags'),
        for (final f in freezes.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GuardrailBanner(
              tone: GuardrailTone.egoFlag,
              title: '${catalog[f.exerciseId]?.name ?? f.exerciseId}: frozen ${_daysLeft(f.until, now)}, '
                  'suggestions 5% below ${formatKg(f.baseWeight)} kg',
              details: f.reason,
            ),
          ),
      ],
    );
  }

  static String _daysLeft(DateTime until, DateTime now) {
    final d = (until.difference(now).inHours / 24).ceil();
    return d <= 1 ? '1 more day' : '$d more days';
  }
}

class _Quests extends ConsumerWidget {
  const _Quests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(questsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Weekly quests',
            trailing: Text('+40 XP each', style: TextStyle(color: AppColors.xp, fontWeight: FontWeight.w700))),
        quests.when(
          loading: () => const Skeleton(height: 170, radius: Radii.card),
          error: (e, _) => Text('$e'),
          data: (list) => GameCard(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              children: [
                for (final q in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: (q.done ? AppColors.primary : AppColors.accent).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(q.done ? Icons.check_rounded : Icons.flag_rounded,
                              color: q.done ? AppColors.primary : AppColors.accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                q.quest.def.title,
                                style: AppType.bodyS.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: q.done ? AppColors.textSecondary : AppColors.textPrimary,
                                  decoration: q.done ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              const SizedBox(height: 6),
                              LpBar(
                                progress: q.progress / q.quest.def.target,
                                color: q.done ? AppColors.primary : AppColors.accent,
                                height: 7,
                                trailing: '${q.progress.clamp(0, q.quest.def.target)}/${q.quest.def.target}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Setting: the day (yyyy-MM-dd) of the last workout of the streak whose loss was already announced.
const _lostSeenKey = 'streak_lost_seen';

class _Streak extends ConsumerStatefulWidget {
  const _Streak();

  @override
  ConsumerState<_Streak> createState() => _StreakState();
}

class _StreakState extends ConsumerState<_Streak> {
  /// Day 4 and later: opening the app after the streak was lost says so once.
  Future<void> _announceLoss(DayStreak s) async {
    final last = s.lastWorkoutDay;
    if (!s.lost || last == null || !mounted) return;
    final db = ref.read(databaseProvider);
    final key = dayKey(last);
    if (await db.getSetting(_lostSeenKey) == key) return;
    if (!mounted) return;
    await db.putSetting(_lostSeenKey, key);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text(DayStreak.lostMessage), duration: Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(dayStreakProvider);
    if (days != null && days.lost) WidgetsBinding.instance.addPostFrameCallback((_) => _announceLoss(days));
    final history = ref.watch(historyProvider).value;
    final now = ref.watch(clockProvider)();
    if (days == null || history == null) {
      return const Padding(padding: EdgeInsets.only(top: 22), child: Skeleton(height: 120, radius: Radii.card));
    }
    final monday = weekStart(now);
    final trained = {for (final s in history.inWeek(now)) dateOnly(s.startedAt)};
    final today = dateOnly(now);
    DayDotState stateFor(DateTime d) {
      if (trained.contains(d)) return DayDotState.trained;
      if (d.isAfter(today)) return DayDotState.future;
      if (d == today) return DayDotState.today;
      return DayDotState.empty;
    }

    final (text, color) = switch (days.safety) {
      StreakSafety.trainedToday => ('Safe: trained today', AppColors.green),
      StreakSafety.safe => ('Safe: trained yesterday, no rest days used', AppColors.green),
      StreakSafety.oneRestDay => ('1 rest day used', AppColors.warning),
      StreakSafety.lastChance => ('Last chance: train today or the streak resets', AppColors.danger),
      StreakSafety.none => ('Your next workout starts a new streak', AppColors.textSecondary),
      StreakSafety.lost => (DayStreak.lostMessage, AppColors.danger),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Streak'),
        GameCard(
          key: const ValueKey('streak-card'),
          onTap: () => context.go(Routes.profile),
          accent: days.days > 0 ? color : null,
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.local_fire_department_rounded, color: AppColors.warning, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${days.days}-day streak', key: const ValueKey('day-streak'), style: AppType.title),
                      Text(
                        days.days > 0 && !days.earnedToday
                            ? 'Longest ${days.longestDays} days · today counts when you finish a workout'
                            : 'Longest ${days.longestDays} days',
                        style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
                      ),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DayDots(states: [for (var i = 0; i < 7; i++) stateFor(addDays(monday, i))]),
              const SizedBox(height: 10),
              Row(children: [
                Icon(
                  days.safety == StreakSafety.lastChance ? Icons.warning_amber_rounded : Icons.shield_outlined,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(text, key: const ValueKey('streak-safety'), style: AppType.bodyS.copyWith(color: color, fontWeight: FontWeight.w700)),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
