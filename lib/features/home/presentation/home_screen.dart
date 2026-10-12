import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../ranks/presentation/progress_screen.dart' show enterBodyweight;
import '../../readiness/presentation/readiness_card.dart';
import '../../workout/presentation/workout_actions.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider).value;
    final bodyweight = ref.watch(latestBodyWeightProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEEE d MMMM').format(now)),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(healthSyncProvider.notifier).sync(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (active != null) ...[
              AppCard(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderColor: AppColors.primary,
                onTap: () => context.push(Routes.workout),
                child: Row(children: [
                  const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Workout in progress', style: TextStyle(color: AppColors.textSecondary)),
                      Text(active.session.name, style: Theme.of(context).textTheme.titleLarge),
                    ]),
                  ),
                  const Text('Resume', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 16)),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            const ReadinessCard(),
            if (bodyweight.hasValue && bodyweight.value == null) ...[
              const SizedBox(height: 12),
              AppCard(
                borderColor: AppColors.warning,
                onTap: () => enterBodyweight(context, ref),
                child: const Row(children: [
                  Icon(Icons.monitor_weight_outlined, color: AppColors.warning),
                  SizedBox(width: 12),
                  Expanded(child: Text('No bodyweight in Apple Health. Tap to enter it so your lifts can be ranked.')),
                ]),
              ),
            ],
            const _EgoFlags(),
            if (active == null) const _NextRoutine(),
            const _StreakLevel(),
            const _Quests(),
          ],
        ),
      ),
    );
  }
}

class _NextRoutine extends ConsumerWidget {
  const _NextRoutine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider).value ?? const [];
    final history = ref.watch(historyProvider).value;
    final catalog = ref.watch(catalogProvider).value ?? const {};
    final lastRoutineId = history?.sessions.reversed.where((s) => s.routineId != null).firstOrNull?.routineId;
    final next = nextRoutine(routines, lastRoutineId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Next up'),
        if (next == null)
          AppCard(
            onTap: () => context.go(Routes.train),
            child: const Row(children: [
              Icon(Icons.add_circle_outline_rounded, color: AppColors.accent),
              SizedBox(width: 12),
              Expanded(child: Text('Create your first routine in the Train tab.')),
            ]),
          )
        else
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(next.routine.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  next.exercises.map((e) => catalog[e.exerciseId]?.name ?? e.exerciseId).join(' · '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: next.exercises.isEmpty ? null : () => startWorkout(context, ref, routine: next),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start workout'),
                ),
                TextButton(onPressed: () => context.go(Routes.train), child: const Text('Pick another routine')),
              ],
            ),
          ),
      ],
    );
  }
}

class _StreakLevel extends ConsumerWidget {
  const _StreakLevel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider);
    final level = ref.watch(levelProvider);
    final week = streak?.thisWeek;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Progress'),
        Row(
          children: [
            Expanded(
              child: AppCard(
                onTap: () => context.go(Routes.profile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatTile(
                      label: 'Weekly streak',
                      value: '${streak?.current ?? 0} wk',
                      icon: Icons.local_fire_department_rounded,
                      color: (streak?.current ?? 0) > 0 ? AppColors.warning : null,
                    ),
                    const SizedBox(height: 8),
                    if (week != null) ...[
                      ProgressBar(value: week.sessions / week.effectiveGoal, color: AppColors.warning, height: 8),
                      const SizedBox(height: 4),
                      Text(
                        '${week.sessions}/${week.effectiveGoal} this week'
                        '${week.smartRestDays > 0 ? ' · ${week.smartRestDays} smart rest' : ''}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppCard(
                onTap: () => context.go(Routes.profile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatTile(label: 'Level', value: '${level.level}', icon: Icons.bolt_rounded, color: AppColors.xp),
                    const SizedBox(height: 8),
                    ProgressBar(value: level.progress, color: AppColors.xp, height: 8),
                    const SizedBox(height: 4),
                    Text('${level.xpIntoLevel}/${level.xpForNext} XP',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
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
        const SectionHeader('Weekly quests'),
        AsyncBody(
          value: quests,
          builder: (list) => AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                for (final q in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(q.done ? Icons.check_circle_rounded : Icons.flag_outlined,
                            color: q.done ? AppColors.primary : AppColors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q.quest.def.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    decoration: q.done ? TextDecoration.lineThrough : null,
                                    color: q.done ? AppColors.textSecondary : AppColors.textPrimary,
                                  )),
                              const SizedBox(height: 6),
                              ProgressBar(
                                value: q.progress / q.quest.def.target,
                                color: q.done ? AppColors.primary : AppColors.accent,
                                height: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('${q.progress.clamp(0, q.quest.def.target)}/${q.quest.def.target}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 6),
                  child: Text('New quests every Monday · +40 XP each',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              ],
            ),
          ),
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
        const SectionHeader('Ego flags'),
        for (final f in freezes.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              borderColor: AppColors.danger,
              onTap: () => context.push(Routes.exercise(f.exerciseId)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_rounded, color: AppColors.danger, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(catalog[f.exerciseId]?.name ?? f.exerciseId,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(f.reason, style: const TextStyle(height: 1.3)),
                        const SizedBox(height: 4),
                        Text(
                          'Frozen ${_daysLeft(f.until, now)} more · suggestions 5% below ${formatKg(f.baseWeight)} kg',
                          style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
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

  static String _daysLeft(DateTime until, DateTime now) {
    final d = (until.difference(now).inHours / 24).ceil();
    return d <= 1 ? '1 day' : '$d days';
  }
}
