import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../gamification/domain/achievements.dart';
import '../../gamification/domain/streaks.dart';
import '../../ranks/domain/ranks.dart';
import '../../ranks/presentation/progress_screen.dart' show enterBodyweight;
import '../../ranks/presentation/rank_badge.dart';

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
      'crown' => Icons.workspace_premium_rounded,
      'compass' => Icons.explore_rounded,
      'leaf' => Icons.eco_rounded,
      'moon' => Icons.bedtime_rounded,
      'calendar' => Icons.event_available_rounded,
      'layers' => Icons.layers_rounded,
      _ => Icons.star_rounded,
    };

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(levelProvider);
    final days = ref.watch(dayStreakProvider);
    final history = ref.watch(historyProvider).value;
    final thisWeek = history == null ? 0 : sessionsThisWeek(history, ref.watch(clockProvider)());
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
          GameCard(
            accent: AppColors.xp,
            glow: true,
            child: Row(
              children: [
                ProgressRing(
                  value: level.progress,
                  color: AppColors.xp,
                  size: 96,
                  stroke: 9,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('LVL', style: AppType.label.copyWith(fontSize: 11, color: AppColors.textSecondary)),
                      Text('${level.level}', style: AppType.displayL.copyWith(height: 1)),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Level ${level.level}', style: AppType.titleL),
                      const SizedBox(height: 10),
                      RrBar(progress: level.progress, color: AppColors.xp, trailing: '${(level.progress * 100).round()}%'),
                      const SizedBox(height: 6),
                      Text('${level.xpIntoLevel} / ${level.xpForNext} XP to level ${level.level + 1}',
                          style: AppType.bodyS.copyWith(color: AppColors.textSecondary, fontFeatures: AppType.tabular)),
                      Text('${NumberFormat.decimalPattern().format(level.totalXp)} XP total',
                          style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w800, color: AppColors.xp)),
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
                        label: 'Streak',
                        value: '${days?.days ?? 0} days',
                        icon: Icons.local_fire_department_rounded,
                        color: AppColors.warning,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Longest: ${days?.longestDays ?? 0} days',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
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
                        value: '$thisWeek',
                        icon: Icons.event_available_rounded,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'session${thisWeek == 1 ? '' : 's'} since Monday',
                        key: const ValueKey('profile-sessions-this-week'),
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
                        style: AppType.number.copyWith(fontSize: 20),
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
                RankBadge(score: overall, size: BadgeSize.small, width: 44, animate: false),
              ],
            ),
          ),
          AsyncBody(
            value: achievements,
            loading: const Padding(padding: EdgeInsets.only(top: 22), child: Skeleton(height: 320, radius: Radii.card)),
            builder: (list) {
              final unlocked = list.where((a) => a.unlockedAt != null).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionLabel('Achievements', trailing: Text('$unlocked/${list.length}',
                      key: const ValueKey('achievements-count'),
                      style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w800, color: AppColors.textSecondary))),
                  for (final cat in AchievementCategory.values)
                    if (list.any((a) => a.def.category == cat)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                        child: Row(children: [
                          Text(cat.label.toUpperCase(), key: ValueKey('achievements-${cat.name}'), style: AppType.label.copyWith(color: AppColors.textSecondary)),
                          const Spacer(),
                          Text('${list.where((a) => a.def.category == cat && a.unlockedAt != null).length}/${list.where((a) => a.def.category == cat).length}',
                              style: AppType.bodyS.copyWith(color: AppColors.textTertiary)),
                        ]),
                      ),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.7,
                        children: [for (final a in list.where((a) => a.def.category == cat)) _AchievementTile(a)],
                      ),
                    ],
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
        ? 'Log sets with a suggestion to measure it.'
        : p >= 85
            ? 'Mostly on the suggestion.'
            : p >= 70
                ? 'Often a different weight than suggested.'
                : 'Mostly your own weights.';
    return GameCard(
      accent: p == null ? null : color,
      child: Row(
        children: [
          ProgressRing(
            value: (p ?? 0) / 100,
            color: color,
            size: 64,
            stroke: 6,
            child: Icon(Icons.gps_fixed_rounded, size: 26, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DISCIPLINE', style: AppType.label.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(p == null ? '—' : '${p.round()}%', style: AppType.displayL.copyWith(color: color)),
                const Text('Working sets within ±5% of the suggestion, or heavier and still inside the rep range, last 30 days. Information only: it never earns or blocks anything.',
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

Color achievementColor(AchievementDef d) => switch (d.level) {
      AchievementLevel.bronze => tierColors[Tier.bronze.index],
      AchievementLevel.silver => tierColors[Tier.silver.index],
      AchievementLevel.gold => tierColors[Tier.gold.index],
      null => switch (d.category) {
          AchievementCategory.consistency => AppColors.primary,
          AchievementCategory.strength => d.type == AchievementType.bestExerciseTier || d.type == AchievementType.overallTier
              ? tierColors[(d.threshold.toInt()).clamp(0, Tier.values.length - 1)]
              : const Color(0xFFFFC93C),
          AchievementCategory.volume => const Color(0xFFFF7A45),
          AchievementCategory.exploration => AppColors.accent,
          AchievementCategory.recovery => AppColors.green,
          AchievementCategory.program => AppColors.xp,
        },
    };

class _AchievementTile extends StatelessWidget {
  const _AchievementTile(this.a);
  final AchievementState a;

  @override
  Widget build(BuildContext context) {
    final unlocked = a.unlockedAt != null;
    final color = achievementColor(a.def);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.card),
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: _Medallion(icon: achievementIcon(a.def.icon), color: color, unlocked: unlocked, progress: a.progress, size: 84),
          title: Text(a.def.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(a.def.description, textAlign: TextAlign.center),
              if (a.def.family != null) ...[
                const SizedBox(height: 6),
                Text('${a.def.family} · ${a.def.level!.label}', style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 12),
              unlocked
                  ? Text('Unlocked ${DateFormat('d MMM yyyy').format(a.unlockedAt!)}',
                      style: AppType.bodyS.copyWith(color: color, fontWeight: FontWeight.w800))
                  : Column(children: [
                      RrBar(progress: a.progress, color: color, trailing: '${(a.progress * 100).round()}%'),
                    ]),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _Medallion(icon: achievementIcon(a.def.icon), color: color, unlocked: unlocked, progress: a.progress, size: 72),
            const SizedBox(height: 8),
            Text(
              a.def.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyS.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: unlocked ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ),
            if (a.def.level != null)
              Text(a.def.level!.label.toUpperCase(),
                  key: ValueKey('level-${a.def.key}'), style: AppType.label.copyWith(fontSize: 9, color: unlocked ? color : AppColors.textTertiary)),
            if (unlocked)
              Text(DateFormat('d MMM').format(a.unlockedAt!), style: AppType.bodyS.copyWith(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Hexagonal medallion. Unlocked: coloured, glowing, with the icon. Locked: dark silhouette with a
/// faint icon, a lock glyph and a progress arc around it.
class _Medallion extends StatelessWidget {
  const _Medallion({required this.icon, required this.color, required this.unlocked, required this.progress, required this.size});
  final IconData icon;
  final Color color;
  final bool unlocked;
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hex = SizedBox(
      width: size * 0.82,
      height: size * 0.82,
      child: CustomPaint(
        painter: _HexPainter(color: unlocked ? color : AppColors.surfaceTop, lit: unlocked),
        child: Center(
          child: Icon(icon, size: size * 0.36, color: unlocked ? Colors.white : AppColors.textTertiary.withValues(alpha: 0.25)),
        ),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!unlocked) ProgressRing(value: progress, color: color.withValues(alpha: 0.8), size: size, stroke: 3),
          hex,
          if (!unlocked)
            Positioned(
              right: size * 0.08,
              bottom: size * 0.06,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: AppColors.background, shape: BoxShape.circle),
                child: Icon(Icons.lock_rounded, size: size * 0.18, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  _HexPainter({required this.color, required this.lit});
  final Color color;
  final bool lit;

  Path _hex(Size s, double inset) {
    final c = s.center(Offset.zero);
    final r = s.shortestSide / 2 - inset;
    return Path()
      ..addPolygon([
        for (var i = 0; i < 6; i++) c + Offset(math.cos(math.pi / 3 * i - math.pi / 2), math.sin(math.pi / 3 * i - math.pi / 2)) * r,
      ], true);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outer = _hex(size, 0);
    final hsl = HSLColor.fromColor(color);
    Color shade(double d) => hsl.withLightness((hsl.lightness + d).clamp(0.0, 1.0)).toColor();
    if (lit) {
      canvas.drawPath(outer, Paint()
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawPath(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: lit ? [shade(0.18), color, shade(-0.22)] : [shade(0.03), color, shade(-0.04)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      _hex(size, size.shortestSide * 0.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = lit ? Colors.white.withValues(alpha: 0.35) : AppColors.outlineBright,
    );
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = lit ? shade(0.25) : AppColors.outline,
    );
  }

  @override
  bool shouldRepaint(covariant _HexPainter old) => old.color != color || old.lit != lit;
}
