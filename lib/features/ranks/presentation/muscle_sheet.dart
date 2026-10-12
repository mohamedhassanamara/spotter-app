import 'package:flutter/material.dart';

import '../../../core/domain/muscle_group.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../domain/body_regions.dart';
import '../domain/ranks.dart';
import 'anatomy_graph.dart';
import 'rank_badge.dart';

Future<void> showMuscleSheet(
  BuildContext context, {
  required MuscleGroup group,
  required BodyGraphMode mode,
  required RankSummary summary,
  required GroupVolume? volume,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: mode == BodyGraphMode.volume
            ? _volumeContent(context, group, volume)
            : _rankContent(context, group, summary),
      ),
    ),
  );
}

List<Widget> _rankContent(BuildContext context, MuscleGroup group, RankSummary summary) {
  final g = summary.groups[group];
  final title = Text(group.label, style: Theme.of(context).textTheme.headlineSmall);
  if (g == null) {
    final hints = summary.unrankedHints[group] ?? const [];
    return [
      Row(children: [const RankBadge(score: null, size: BadgeSize.medium), const SizedBox(width: 16), Expanded(child: title)]),
      const SizedBox(height: 16),
      Text(
        hints.isEmpty ? 'No ranked lift trains this group yet.' : 'Unranked. Log any of these to place it on the ladder:',
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      for (final s in hints)
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.add_circle_outline_rounded), title: Text(s.name)),
    ];
  }
  final color = tierColors[g.score.tier.index];
  final step = groupNextStep(g);
  return [
    Row(
      children: [
        RankBadge(score: g.score, size: BadgeSize.medium, width: 84),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              Text(g.score.label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 8),
              ProgressBar(value: g.score.divisionProgress, color: color),
              const SizedBox(height: 4),
              Text(
                g.score.nextLabel == null ? '${g.score.lp} LP · top of the ladder' : '${g.score.lp} LP · next: ${g.score.nextLabel}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
    if (step != null) ...[
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.flag_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '+${formatKg((step.kg.clamp(0, double.infinity) * 10).ceilToDouble() / 10)} kg e1RM on ${step.standard.name} '
              'moves ${group.label} to ${step.nextLabel}.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    ],
    const SizedBox(height: 16),
    const Text('CONTRIBUTING LIFTS', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
    for (final c in g.contributions)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: RankBadge(score: c.rank.score, size: BadgeSize.small, width: 36, animate: false),
        title: Text(c.rank.standard.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${c.rank.score.labelWithLp} · e1RM ${c.rank.bestE1rm.toStringAsFixed(1)} kg'
          '${c.rank.nextThresholdKg == null ? '' : ' · next at ${c.rank.nextThresholdKg!.toStringAsFixed(1)} kg'}',
        ),
        trailing: Text(c.weight >= 1 ? 'primary' : 'secondary', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ),
  ];
}

List<Widget> _volumeContent(BuildContext context, MuscleGroup group, GroupVolume? v) {
  final level = volumeLevel(v);
  final color = volumeColor(level);
  final ratio = v?.ratio;
  return [
    Row(children: [
      Container(width: 18, height: 18, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Text(group.label, style: Theme.of(context).textTheme.headlineSmall),
      const Spacer(),
      Text(volumeLabel(level), style: TextStyle(color: color, fontWeight: FontWeight.w900)),
    ]),
    const SizedBox(height: 16),
    Row(children: [
      Expanded(child: StatTile(label: 'Last 7 days', value: '${v?.recentSets ?? 0} sets')),
      Expanded(child: StatTile(label: '4-week avg / week', value: (v?.weeklyAverage ?? 0).toStringAsFixed(1))),
      Expanded(child: StatTile(label: 'Ratio', value: ratio == null ? '—' : '${(ratio * 100).round()}%', color: color)),
    ]),
    const SizedBox(height: 16),
    Text(
      switch (level) {
        VolumeLevel.none => 'No working sets for this group in the last 5 weeks.',
        VolumeLevel.under => 'Well below your usual week. A good target for your next session.',
        VolumeLevel.low => 'A little under your usual weekly volume.',
        VolumeLevel.onTrack => 'In line with your usual weekly volume.',
        VolumeLevel.high => 'Above 1.5× your usual week: the coach lowers readiness by 10 for exercises that train it.',
        VolumeLevel.new_ => 'Trained this week with no 4-week history yet.',
      },
      style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
    ),
    const SizedBox(height: 8),
    const Text('Counts working sets where this is a primary muscle.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
  ];
}
