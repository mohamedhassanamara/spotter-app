import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/domain/muscles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../coach/domain/suggestion_engine.dart' show formatKg;
import '../domain/ranks.dart';
import 'rank_badge.dart';

/// Every tier of the ladder with its badges (all divisions), what each one asks for at your bodyweight, where you
/// sit now, and where each muscle sits.
class LadderScreen extends ConsumerWidget {
  const LadderScreen({super.key});

  /// The reference lifts the requirements are quoted for.
  static const referenceStandards = ['bench_press', 'back_squat', 'deadlift'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(ranksProvider).value;
    final standards = ref.watch(standardsProvider).value ?? const <StrengthStandard>[];
    final bw = ref.watch(latestBodyWeightProvider).value?.kg ?? 0;
    final overall = summary?.overall;
    return Scaffold(
      appBar: AppBar(title: const Text('The ladder')),
      body: ListView(
        key: const ValueKey('ladder-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Nine tiers, Iron to Immortal. Iron to Olympian have three divisions each (1 → 3, 3 is the highest), each worth 37.5 strength; '
            'Immortal has none, only RR. Every lift is scored from its best valid set in the last 90 days against a strength standard.',
            style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          for (final t in Tier.values.reversed) ...[
            _TierCard(tier: t, overall: overall, standards: standards, bodyweight: bw, exercises: summary?.exercises ?? const []),
            const SizedBox(height: 10),
          ],
          const SectionLabel('Where each muscle sits'),
          if (summary == null || summary.muscles.isEmpty)
            Text('No muscle is ranked yet.', style: AppType.bodyS.copyWith(color: AppColors.textSecondary))
          else
            for (final m in ([...summary.muscles.values]..sort((a, b) => b.score.value.compareTo(a.score.value))))
              _MuscleOnLadder(key: ValueKey('ladder-muscle-${m.muscle.name}'), muscle: m.muscle, score: m.score),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.overall, required this.standards, required this.bodyweight, required this.exercises});
  final Tier tier;
  final List<ExerciseRank> exercises;
  final RankScore? overall;
  final List<StrengthStandard> standards;
  final double bodyweight;

  /// Points at which each division of the tier starts (1 → 3), or the single Immortal entry.
  List<double> get starts {
    if (tier.isApex) return [tierStart];
    return [for (var d = 0; d < 3; d++) tier.index * 3.0 + d];
  }

  double get tierStart => tier.isApex ? RankScore.apexPoints : tier.index * 3.0;

  @override
  Widget build(BuildContext context) {
    final here = overall?.tier == tier;
    final color = tierColor(tier);
    final lifts = [
      for (final id in LadderScreen.referenceStandards)
        if (standards.any((s) => s.id == id)) standards.firstWhere((s) => s.id == id),
    ];
    return GameCard(
      key: ValueKey('ladder-tier-${tier.name}'),
      accent: here ? color : null,
      glow: here,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(tier.label.toUpperCase(), style: AppType.title.copyWith(color: color)),
          const Spacer(),
          if (here)
            Container(
              key: const ValueKey('ladder-you-are-here'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.chip)),
              child: Text('YOU ARE HERE · ${overall!.label} · ${overall!.rr} RR',
                  style: AppType.label.copyWith(fontSize: 11, color: const Color(0xFF10131A))),
            ),
        ]),
        const SizedBox(height: 10),
        if (bodyweight <= 0)
          Text('Add your bodyweight to see what it takes.', style: AppType.bodyS.copyWith(color: AppColors.textSecondary))
        else ...[
          Text('At ${formatKg(bodyweight)} kg bodyweight (best set, e1RM)', style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Table(
            key: ValueKey('ladder-table-${tier.name}'),
            columnWidths: {0: const FlexColumnWidth(1.6), for (var c = 1; c <= starts.length; c++) c: const FlexColumnWidth(1)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                const SizedBox.shrink(),
                for (final p in starts)
                  Column(children: [
                    RankBadge(score: RankScore(p), size: BadgeSize.small, width: 34, animate: false),
                    Text(tier.isApex ? '' : RankScore(p).divisionLabel, style: AppType.label.copyWith(fontSize: 11, color: AppColors.textSecondary)),
                  ]),
              ]),
              for (final s in lifts)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(s.name, style: AppType.bodyS)),
                  for (final p in starts) _cell(s, p, color),
                ]),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in lifts)
            Text('${s.name}: ${_mine(s)}', style: AppType.bodyS.copyWith(color: AppColors.textSecondary, fontFeatures: AppType.tabular)),
        ],
      ]),
    );
  }

  /// My best e1RM on a standard's lifts, null when there is none.
  double? _e1rm(StrengthStandard s) {
    final mine = [for (final e in exercises) if (e.standard.id == s.id) e.bestE1rm];
    return mine.isEmpty ? null : mine.reduce((a, b) => a > b ? a : b);
  }

  /// "You: 78 kg" (kg from the same e1RM the thresholds are quoted in).
  String _mine(StrengthStandard s) {
    final e = _e1rm(s);
    return e == null ? 'You: –' : 'You: ${formatKg(e)} kg';
  }

  /// The division cell I am in on this lift is lit.
  Widget _cell(StrengthStandard s, double points, Color color) {
    final e = _e1rm(s);
    final next = tier.isApex ? double.infinity : points + 1;
    final mine = e != null && bodyweight > 0 && (() {
      final v = s.scoreForRatio(e / s.normalizer(bodyweight)).value;
      return v + 1e-9 >= points && v < next;
    })();
    return Container(
      key: mine ? ValueKey('ladder-me-${tier.name}-${s.id}') : null,
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: mine ? color.withValues(alpha: 0.25) : null,
        border: mine ? Border.all(color: color, width: 1.5) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(_kg(s, points), textAlign: TextAlign.center, style: AppType.bodyS.copyWith(fontFeatures: AppType.tabular, fontWeight: mine ? FontWeight.w800 : null)),
    );
  }

  String _kg(StrengthStandard s, double points) => '${(s.ratioForPoints(points) * s.normalizer(bodyweight)).round()} kg';
}

class _MuscleOnLadder extends StatelessWidget {
  const _MuscleOnLadder({super.key, required this.muscle, required this.score});
  final Muscle muscle;
  final RankScore score;

  @override
  Widget build(BuildContext context) {
    const top = RankScore.apexPoints + 2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 110, child: Text(muscle.label, style: AppType.body)),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return SizedBox(
              height: 18,
              child: Stack(clipBehavior: Clip.none, children: [
                Row(children: [
                  for (final t in Tier.values)
                    Expanded(
                      flex: t == Tier.immortal ? 2 : 3,
                      child: Container(height: 8, margin: const EdgeInsets.only(top: 5, right: 1), color: tierColor(t).withValues(alpha: 0.45)),
                    ),
                ]),
                Positioned(
                  left: (score.value / top).clamp(0.0, 1.0) * w - 6,
                  top: 1,
                  child: Container(
                    width: 12,
                    height: 16,
                    decoration: BoxDecoration(color: tierColor(score.tier), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white, width: 2)),
                  ),
                ),
              ]),
            );
          }),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 92, child: Text(score.label, textAlign: TextAlign.right, style: AppType.bodyS.copyWith(color: tierColor(score.tier), fontWeight: FontWeight.w800))),
      ]),
    );
  }
}
