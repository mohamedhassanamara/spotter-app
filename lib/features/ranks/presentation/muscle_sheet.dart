import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';

import '../../../core/domain/muscles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../domain/body_regions.dart';
import '../domain/bodyweight_what_if.dart';
import '../domain/rank_target.dart';
import '../domain/ranks.dart';
import 'rank_target_line.dart';
import 'anatomy_graph.dart';
import '../../recovery/domain/recovery.dart';
import '../../recovery/domain/recovery_config.dart';
import 'rank_badge.dart';
import 'rank_toggle.dart';

Future<void> showMuscleSheet(
  BuildContext context, {
  required Muscle group,
  required BodyGraphMode mode,
  required RankSummary summary,
  required GroupVolume? volume,
  MuscleRecovery? recovery,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      // Live: toggling "Counts toward rank" on a row recomputes and redraws the sheet at once.
      builder: (context, scroll) => Consumer(
        builder: (context, ref, _) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(context).bottom),
          children: switch (mode) {
            BodyGraphMode.volume => _volumeContent(context, group, volume),
            BodyGraphMode.recovery => recoveryContent(context, group, recovery),
            BodyGraphMode.ranks => _rankContent(context, group, ref.watch(ranksProvider).value ?? summary),
          },
        ),
      ),
    ),
  );
}

/// One exercise feeding (or switched off from) a muscle, with its "Counts toward rank" switch.
Widget _exerciseRow(ExerciseRank r, double weight, {required bool counted}) => Opacity(
      key: ValueKey('muscle-exercise-${r.exerciseId}'),
      opacity: counted ? 1 : 0.55,
      child: Builder(builder: (context) => ListTile(
        // Opens the exercise (the same name the logger shows).
        onTap: () {
          Navigator.of(context).pop();
          context.push(Routes.exercise(r.exerciseId));
        },
        contentPadding: EdgeInsets.zero,
        leading: RankBadge(score: r.score, size: BadgeSize.small, width: 36, animate: false),
        title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(counted
            ? '${r.score.labelWithRr} · ${r.strength} · ×${weight.toStringAsFixed(weight == weight.roundToDouble() ? 0 : 1)} · ${liftLine(r)}'
            : 'Not counted · ${r.score.label} · ${liftLine(r)}'),
        trailing: RankToggle(exerciseId: r.exerciseId),
      )),
    );

List<Widget> _hiddenRows(RankSummary summary, Muscle muscle) => [
      for (final r in summary.hidden)
        if (r.targets.weightFor(muscle) > 0) _exerciseRow(r, r.targets.weightFor(muscle), counted: false),
    ];

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
      if (_hiddenRows(summary, muscle).isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('NOT COUNTED', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
        ..._hiddenRows(summary, muscle),
      ],
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
                '${g.score.nextLabel == null ? '${g.score.rr} RR · top of the ladder' : '${g.score.rr} RR · next: ${g.score.nextLabel}'}'
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
            child: Consumer(
              builder: (context, ref, _) {
                final r = step.rank;
                final grid = ref.watch(exerciseGridProvider(r.exerciseId));
                final rx = ref.watch(rankPrescriptionProvider(r.exerciseId));
                const style = TextStyle(fontWeight: FontWeight.w700);
                if (ref.watch(rankTargetModeProvider) == RankTargetMode.bodyweight) {
                  final t = bodyweightTargetForMuscle(g, ref.watch(currentBodyweightProvider));
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    whatIfText(muscleBodyweightTargetLine(t, g.score.nextLabel, muscle.label) ?? '', key: ValueKey('muscle-next-step-${muscle.name}'), style: style),
                    const SizedBox(height: 6),
                    const RankTargetModeToggle(),
                  ]);
                }
                final set = grid == null
                    ? null
                    : rankTargetSet(standard: r.standard, bodyweight: r.bodyweight, targetE1rm: step.targetE1rm, repMin: rx.repMin, rir: rx.rir, grid: grid);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    set == null
                        ? '${r.name}: $rankTargetUnreachable'
                        : 'Next step: ${set.text} on ${r.name} moves ${muscle.label} to ${step.nextLabel}.',
                    key: ValueKey('muscle-next-step-${muscle.name}'),
                    style: style,
                  ),
                  const SizedBox(height: 6),
                  const RankTargetModeToggle(),
                ]);
              },
            ),
          ),
        ]),
      ),
    ],
    const SizedBox(height: 16),
    const Text('CONTRIBUTING EXERCISES', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
    for (final c in g.contributions) _exerciseRow(c.rank, c.weight, counted: true),
    ..._hiddenRows(summary, muscle),
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

/// "in 1 d 4 h" / "in 5 h" / "now".
String formatHoursToReady(double h) {
  if (h <= 0) return 'now';
  final total = h.ceil();
  if (total < 24) return 'in $total h';
  final d = total ~/ 24, rest = total % 24;
  return rest == 0 ? 'in $d d' : 'in $d d $rest h';
}

List<Widget> recoveryContent(BuildContext context, Muscle muscle, MuscleRecovery? r) {
  final band = r?.band;
  final color = recoveryColor(band);
  final pct = r?.pct ?? 100;
  return [
    Row(children: [
      MuscleThumbnail(muscle: muscle, color: color, size: 64),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(muscle.region.label.toUpperCase(), style: AppType.label.copyWith(color: AppColors.textSecondary)),
          Text(muscle.label, style: Theme.of(context).textTheme.headlineSmall),
          Text(band?.label ?? 'Ready', key: const ValueKey('recovery-band'), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)),
        ]),
      ),
      Text('${pct.round()}%', key: const ValueKey('recovery-pct'), style: AppType.displayL.copyWith(color: color)),
    ]),
    const SizedBox(height: 12),
    ProgressBar(value: pct / 100, color: color),
    const SizedBox(height: 16),
    Row(children: [
      Expanded(
        child: StatTile(
          label: 'Ready',
          value: r == null || r.hoursToReady <= 0 ? 'now' : formatHoursToReady(r.hoursToReady),
          color: color,
        ),
      ),
      Expanded(
        child: StatTile(
          label: 'Last trained',
          value: r?.lastHitAt == null ? '—' : DateFormat('EEE d MMM').format(r!.lastHitAt!),
        ),
      ),
    ]),
    if (r?.lastSession != null) ...[
      const SizedBox(height: 8),
      Text('Last session that hit it: ${r!.lastSession} · ${DateFormat('EEE d MMM, HH:mm').format(r.lastHitAt!)}',
          key: const ValueKey('recovery-last-session'), style: const TextStyle(color: AppColors.textSecondary)),
    ],
    const SizedBox(height: 16),
    Text(
      'A heuristic: each working set adds fatigue (contribution × effort; drops count half) that fades with a '
      '${RecoveryConfig.halfLifeH(muscle).round()} h half-life for this muscle, slower on Yellow and Red readiness days. '
      'It never changes your suggestions.',
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
    ),
  ];
}
