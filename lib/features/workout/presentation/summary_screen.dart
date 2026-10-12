import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(lastSummaryProvider);
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.check_circle_outline,
          title: 'Nothing to show',
          message: 'Finish a workout to see its summary.',
          action: FilledButton(onPressed: () => context.go(Routes.home), child: const Text('Home')),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Workout complete')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: () => context.go(Routes.home), child: const Text('Done')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.name, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          AppCard(
            child: Row(
              children: [
                Expanded(child: StatTile(label: 'Duration', value: formatDuration(s.duration), icon: Icons.timer_outlined)),
                Expanded(child: StatTile(label: 'Volume', value: formatVolume(s.volume), icon: Icons.stacked_bar_chart)),
                Expanded(child: StatTile(label: 'Sets', value: '${s.workingSets}', icon: Icons.repeat_rounded)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            borderColor: AppColors.xp.withValues(alpha: 0.6),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: AppColors.xp, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('+${s.xpTotal} XP',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.xp)),
                      Text(
                        [
                          '${s.xpSession} from sets and PRs',
                          if (s.xpBonus > 0) '${s.xpBonus} bonus',
                        ].join(' · '),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (s.levelAfter > s.levelBefore)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: AppColors.xp, borderRadius: BorderRadius.circular(12)),
                    child: Text('LEVEL ${s.levelAfter}!',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1B0B33))),
                  ),
              ],
            ),
          ),
          if (s.weeklyGoalReached) ...[
            const SizedBox(height: 12),
            const AppCard(
              borderColor: AppColors.primary,
              child: Row(children: [
                Icon(Icons.local_fire_department_rounded, color: AppColors.primary, size: 32),
                SizedBox(width: 12),
                Expanded(child: Text('Weekly goal complete! +100 XP', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              ]),
            ),
          ],
          if (s.flags.isNotEmpty || s.overrideSets > 0) ...[
            const SectionHeader('Guardrail'),
            if (s.overrideSets > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${s.overrideSets} override set${s.overrideSets == 1 ? '' : 's'} today. They earned no XP; '
                        'at RPE 9.5+ they don\'t count for ranks or PRs.',
                      ),
                    ),
                  ]),
                ),
              ),
            for (final f in s.flags)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  borderColor: AppColors.danger,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lock_rounded, color: AppColors.danger),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.exerciseName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(f.message),
                            if (f.freezeUntil != null)
                              Text('Frozen until ${DateFormat('EEE d MMM').format(f.freezeUntil!)}',
                                  style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (s.prs.isNotEmpty) ...[
            const SectionHeader('Personal records'),
            for (final p in s.prs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFC93C)),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('e1RM ${p.e1rm.toStringAsFixed(1)} kg (was ${p.previous.toStringAsFixed(1)})'),
                trailing: const Text('+50 XP', style: TextStyle(color: AppColors.xp, fontWeight: FontWeight.w800)),
              ),
          ],
          if (s.rankChanges.isNotEmpty) ...[
            const SectionHeader('Rank changes'),
            for (final r in s.rankChanges)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(r.up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                    color: r.up ? AppColors.primary : AppColors.danger),
                title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(r.from == null ? 'Ranked: ${r.to}' : '${r.from} → ${r.to}'),
              ),
          ],
          if (s.achievements.isNotEmpty) ...[
            const SectionHeader('Achievements unlocked'),
            for (final a in s.achievements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.military_tech_rounded, color: AppColors.xp),
                title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(a.description),
              ),
          ],
          if (s.questsCompleted.isNotEmpty) ...[
            const SectionHeader('Quests completed'),
            for (final q in s.questsCompleted)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_rounded, color: AppColors.accent),
                title: Text(q),
                trailing: const Text('+40 XP', style: TextStyle(color: AppColors.xp, fontWeight: FontWeight.w800)),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                s.healthSaved == true ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: s.healthSaved == true ? AppColors.danger : AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.healthSaved == true
                      ? 'Saved to Apple Health as Traditional Strength Training.'
                      : 'Not saved to Apple Health (no write permission or Health unavailable).',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
