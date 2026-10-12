import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../ranks/presentation/progress_screen.dart' show enterBodyweight;

IconData achievementIcon(String name) => switch (name) {
      'fitness' => Icons.fitness_center_rounded,
      'trophy' => Icons.emoji_events_rounded,
      'shield' => Icons.shield_rounded,
      'bed' => Icons.bedtime_rounded,
      'trending' => Icons.trending_up_rounded,
      'target' => Icons.gps_fixed_rounded,
      'fire' => Icons.local_fire_department_rounded,
      'rank' => Icons.military_tech_rounded,
      'star' => Icons.star_rounded,
      'weight' => Icons.scale_rounded,
      'bolt' => Icons.bolt_rounded,
      _ => Icons.star_rounded,
    };

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(levelProvider);
    final streak = ref.watch(streakProvider);
    final discipline = ref.watch(disciplineProvider);
    final bw = ref.watch(latestBodyWeightProvider).value;
    final overall = ref.watch(ranksProvider).value?.overall;
    final achievements = ref.watch(achievementsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            iconSize: 28,
            tooltip: 'Settings',
            onPressed: () => context.push(Routes.settings),
            icon: const Icon(Icons.settings_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Level
          AppCard(
            borderColor: AppColors.xp.withValues(alpha: 0.5),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: level.progress,
                        strokeWidth: 8,
                        backgroundColor: AppColors.surfaceHigh,
                        valueColor: const AlwaysStoppedAnimation(AppColors.xp),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('LVL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
                            Text('${level.level}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, height: 1)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Level ${level.level}', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      ProgressBar(value: level.progress, color: AppColors.xp),
                      const SizedBox(height: 6),
                      Text('${level.xpIntoLevel} / ${level.xpForNext} XP to level ${level.level + 1}',
                          style: const TextStyle(color: AppColors.textSecondary)),
                      Text('${NumberFormat.decimalPattern().format(level.totalXp)} XP total',
                          style: const TextStyle(color: AppColors.xp, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Streak + this week
          Row(
            children: [
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatTile(
                        label: 'Weekly streak',
                        value: '${streak?.current ?? 0} wk',
                        icon: Icons.local_fire_department_rounded,
                        color: AppColors.warning,
                      ),
                      const SizedBox(height: 6),
                      Text('Longest: ${streak?.longest ?? 0} wk', style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatTile(
                        label: 'This week',
                        value: '${streak?.thisWeek.sessions ?? 0}/${streak?.thisWeek.effectiveGoal ?? ref.watch(currentSettingsProvider).weeklyGoal}',
                        icon: Icons.event_available_rounded,
                        color: (streak?.thisWeek.met ?? false) ? AppColors.green : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (streak?.thisWeek.smartRestDays ?? 0) > 0
                            ? '${streak!.thisWeek.smartRestDays} smart rest day${streak.thisWeek.smartRestDays == 1 ? '' : 's'} used'
                            : 'No smart rest used',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DisciplineCard(pct: discipline),
          const SizedBox(height: 12),
          // Bodyweight + overall rank
          AppCard(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            onTap: () => enterBodyweight(context, ref),
            child: Row(
              children: [
                const Icon(Icons.monitor_weight_outlined, size: 28, color: AppColors.textSecondary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bw == null ? 'Bodyweight not set' : '${bw.kg.toStringAsFixed(1)} kg',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        bw == null
                            ? 'Tap to enter — needed for ranks'
                            : '${bw.source == 'health' ? 'Apple Health' : 'Manual'} · ${DateFormat('d MMM').format(bw.measuredAt)} · tap to update',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                TierBadge(overall),
              ],
            ),
          ),
          AsyncBody(
            value: achievements,
            builder: (list) {
              final unlocked = list.where((a) => a.unlockedAt != null).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader('Achievements', trailing: Text('$unlocked/${list.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textSecondary))),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.82,
                    children: [for (final a in list) _AchievementTile(a)],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DisciplineCard extends StatelessWidget {
  const _DisciplineCard({required this.pct});
  final double? pct;

  @override
  Widget build(BuildContext context) {
    final p = pct;
    final color = p == null
        ? AppColors.textSecondary
        : p >= 85
            ? AppColors.green
            : p >= 70
                ? AppColors.yellow
                : AppColors.red;
    final verdict = p == null
        ? 'Log sets with the coach to measure it.'
        : p >= 85
            ? 'Disciplined. You lift what the coach prescribes.'
            : p >= 70
                ? 'Mostly on plan. Watch the overrides.'
                : 'Lots of overrides. Ego is driving.';
    return AppCard(
      borderColor: color.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(Icons.gps_fixed_rounded, size: 34, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DISCIPLINE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(p == null ? '—' : '${p.round()}%', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: color)),
                const Text('Working sets within ±5% of the suggestion, last 30 days',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text(verdict, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile(this.a);
  final AchievementState a;

  @override
  Widget build(BuildContext context) {
    final unlocked = a.unlockedAt != null;
    final color = unlocked ? AppColors.xp : AppColors.textSecondary;
    return AppCard(
      padding: const EdgeInsets.all(10),
      color: unlocked ? AppColors.xp.withValues(alpha: 0.10) : null,
      borderColor: unlocked ? AppColors.xp.withValues(alpha: 0.6) : null,
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(achievementIcon(a.def.icon), size: 40, color: color),
          title: Text(a.def.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(a.def.description, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              unlocked
                  ? Text('Unlocked ${DateFormat('d MMM yyyy').format(a.unlockedAt!)}',
                      style: const TextStyle(color: AppColors.xp, fontWeight: FontWeight.w800))
                  : Column(children: [
                      ProgressBar(value: a.progress, color: AppColors.xp),
                      const SizedBox(height: 6),
                      Text('${(a.progress * 100).round()}% there', style: const TextStyle(color: AppColors.textSecondary)),
                    ]),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!unlocked)
                  CircularProgressIndicator(
                    value: a.progress,
                    strokeWidth: 3.5,
                    backgroundColor: AppColors.surfaceHigh,
                    valueColor: const AlwaysStoppedAnimation(AppColors.xp),
                  ),
                Center(
                  child: Icon(achievementIcon(a.def.icon), size: unlocked ? 36 : 26, color: unlocked ? AppColors.xp : AppColors.unranked),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            a.def.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: unlocked ? AppColors.textPrimary : AppColors.textSecondary),
          ),
          if (unlocked)
            Text(DateFormat('d MMM').format(a.unlockedAt!), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
