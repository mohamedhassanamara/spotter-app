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
            'Nine tiers, Iron to Radiant. Iron to Immortal have three divisions each (1 → 3, 3 is the highest), each worth 37.5 strength; '
            'Radiant has none, only RR. Every lift is scored from its best valid set in the last 90 days against a strength standard.',
            style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          for (final t in Tier.values.reversed) ...[
            _TierCard(tier: t, overall: overall, standards: standards, bodyweight: bw),
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
  const _TierCard({required this.tier, required this.overall, required this.standards, required this.bodyweight});
  final Tier tier;
  final RankScore? overall;
  final List<StrengthStandard> standards;
  final double bodyweight;

  /// Points at which each division of the tier starts (1 → 3), or the single Radiant entry.
  List<double> get starts {
    if (tier.isApex) return [tierStart];
    return [for (var d = 0; d < 3; d++) tier.index * 3.0 + d];
  }

  double get tierStart => tier.isApex ? RankScore.radiantPoints : tier.index * 3.0;

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
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final p in starts)
            Column(children: [
              RankBadge(score: RankScore(p), size: BadgeSize.small, width: tier.isApex ? 64 : 52, animate: false),
              const SizedBox(height: 2),
              Text(tier.isApex ? '' : RankScore(p).divisionLabel, style: AppType.label.copyWith(fontSize: 11, color: AppColors.textSecondary)),
            ]),
        ]),
        const SizedBox(height: 10),
        if (bodyweight <= 0)
          Text('Add your bodyweight to see what it takes.', style: AppType.bodyS.copyWith(color: AppColors.textSecondary))
        else ...[
          Text('To enter ${tier.label}${tier.isApex ? '' : ' 1'} at ${formatKg(bodyweight)} kg (best set, e1RM):',
              style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          for (final s in lifts)
            Text('${s.name}: ${_kg(s, tierStart)}${tier.isApex ? '' : '  ·  1 ${_kg(s, starts[0], bare: true)} · 2 ${_kg(s, starts[1], bare: true)} · 3 ${_kg(s, starts[2], bare: true)}'}',
                style: AppType.bodyS.copyWith(fontFeatures: AppType.tabular)),
        ],
      ]),
    );
  }

  String _kg(StrengthStandard s, double points, {bool bare = false}) {
    final kg = s.ratioForPoints(points) * s.normalizer(bodyweight);
    return bare ? '${kg.round()}' : '${kg.round()} kg';
  }
}

class _MuscleOnLadder extends StatelessWidget {
  const _MuscleOnLadder({super.key, required this.muscle, required this.score});
  final Muscle muscle;
  final RankScore score;

  @override
  Widget build(BuildContext context) {
    const top = RankScore.radiantPoints + 2;
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
                      flex: t == Tier.radiant ? 2 : 3,
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
