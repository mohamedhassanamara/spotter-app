import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/domain/muscles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../domain/body_regions.dart';
import '../domain/ranks.dart';
import 'anatomy_graph.dart';
import 'rank_badge.dart';

Future<void> showMuscleSheet(
  BuildContext context, {
  required Muscle group,
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

List<Widget> _rankContent(BuildContext context, Muscle muscle, RankSummary summary) {
  final g = summary.muscles[muscle];
  final title = Text(muscle.label, style: Theme.of(context).textTheme.headlineSmall);
  final region = Text(muscle.region.label.toUpperCase(), style: AppType.label.copyWith(color: AppColors.textSecondary));
  if (g == null) {
    final hints = summary.unrankedHints[muscle] ?? const [];
    return [
      Row(children: [
        MuscleThumbnail(muscle: muscle, color: AppColors.unranked, size: 64),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [region, title, const Text('Unranked')])),
      ]),
      const SizedBox(height: 16),
      Text(
        hints.isEmpty
            ? 'None of your exercises trains ${muscle.label.toLowerCase()} as a main muscle yet. Add one that does to rank it.'
            : 'Unranked. Log any of these (from your routines and history) to place it on the ladder:',
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      for (final h in hints)
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.add_circle_outline_rounded), title: Text(h.name)),
    ];
  }
  final color = tierColors[g.score.tier.index];
  final step = muscleNextStep(g);
  return [
    Row(
      children: [
        RankBadge(score: g.score, size: BadgeSize.medium, width: 84),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              region,
              title,
              Text(g.score.label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 8),
              ProgressBar(value: g.score.divisionProgress, color: color),
              const SizedBox(height: 4),
              Text(
                '${g.score.nextLabel == null ? '${g.score.lp} LP · top of the ladder' : '${g.score.lp} LP · next: ${g.score.nextLabel}'}'
                ' · strength ${g.score.strength}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        MuscleThumbnail(muscle: muscle, color: color, size: 56),
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
              '+${formatKg((step.kg.clamp(0, double.infinity) * 10).ceilToDouble() / 10)} kg e1RM on ${step.rank.name} '
              'moves ${muscle.label} to ${step.nextLabel}.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    ],
    const SizedBox(height: 16),
    const Text('CONTRIBUTING EXERCISES', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
    for (final c in g.contributions)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: RankBadge(score: c.rank.score, size: BadgeSize.small, width: 36, animate: false),
        title: Text(c.rank.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${c.rank.score.labelWithLp} · ${c.rank.strength} · ${liftLine(c.rank)}'),
        trailing: Text('×${c.weight.toStringAsFixed(c.weight == c.weight.roundToDouble() ? 0 : 1)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ),
    const SizedBox(height: 8),
    const Text(
      'A muscle\'s rank is the weighted average of its exercises\' best strength scores in the last 90 days '
      '(×1 = prime mover, lower = helper). Each set is scored against your bodyweight on that day.',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
  ];
}

/// "65 kg × 6 on 6 Oct · 106.5 kg BW".
String liftLine(ExerciseRank r) {
  final load = r.weight < 0 ? '${formatKg(-r.weight)} kg assist' : (r.weight == 0 ? 'BW' : '${formatKg(r.weight)} kg');
  return '$load × ${r.reps} on ${DateFormat('d MMM').format(r.date)} · ${formatKg(r.bodyweight)} kg BW';
}

List<Widget> _volumeContent(BuildContext context, Muscle group, GroupVolume? v) {
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
    const Text('Counts working sets where this muscle does at least half the work (contribution ≥ 0.5).', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
  ];
}
