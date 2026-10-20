import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/domain/muscles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/rank_history.dart';
import '../domain/ranks.dart';

/// What the chart follows: the overall rank, a body region or one muscle.
sealed class EvolutionSeries {
  const EvolutionSeries();
  String get label;
  String get id;
  RankScore? at(RankPoint p);
}

class OverallSeries extends EvolutionSeries {
  const OverallSeries();
  @override
  String get label => 'Overall';
  @override
  String get id => 'overall';
  @override
  RankScore? at(RankPoint p) => p.overall;
}

class RegionSeries extends EvolutionSeries {
  const RegionSeries(this.region);
  final BodyRegion region;
  @override
  String get label => region.label;
  @override
  String get id => 'region-${region.name}';
  @override
  RankScore? at(RankPoint p) => p.regions[region];
}

class MuscleSeries extends EvolutionSeries {
  const MuscleSeries(this.muscle);
  final Muscle muscle;
  @override
  String get label => muscle.label;
  @override
  String get id => 'muscle-${muscle.name}';
  @override
  RankScore? at(RankPoint p) => p.muscles[muscle];
}

/// The y range [low, high) of one tier in points, for the background bands.
(double, double) tierBand(Tier t) {
  if (t == Tier.immortal) return (RankScore.apexPoints, RankScore.apexPoints + 3);
  return (t.index * 3.0, t.index * 3.0 + 3);
}

/// Progress → Ranks: the rank over time with the tier bands behind it, the imported history included.
/// Pick a region or a muscle to see its own line.
class RankEvolutionCard extends ConsumerStatefulWidget {
  const RankEvolutionCard({super.key});

  @override
  ConsumerState<RankEvolutionCard> createState() => _RankEvolutionCardState();
}

class _RankEvolutionCardState extends ConsumerState<RankEvolutionCard> {
  EvolutionSeries _series = const OverallSeries();

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rankEvolutionProvider);
    return GameCard(
      key: const ValueKey('rank-evolution'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: async.when(
        loading: () => const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text('Could not build the rank history: $e'),
        data: (points) {
          final line = [for (final p in points) if (_series.at(p) != null) (p, _series.at(p)!)];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('RANK EVOLUTION', style: AppType.label.copyWith(color: AppColors.textSecondary))),
              if (line.isNotEmpty)
                Text(line.last.$2.label, key: const ValueKey('evolution-now'), style: AppType.bodyS.copyWith(color: tierColor(line.last.$2.tier), fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 2),
            Text(_series.label, key: const ValueKey('evolution-series'), style: AppType.title),
            const SizedBox(height: 10),
            SizedBox(
              height: 230,
              child: line.length < 2
                  ? Center(child: Text('Log a few weeks of ranked lifts to draw this.', style: AppType.bodyS.copyWith(color: AppColors.textSecondary)))
                  : _Chart(key: ValueKey('chart-${_series.id}'), line: line),
            ),
            const SizedBox(height: 10),
            _picker(),
          ]);
        },
      ),
    );
  }

  Widget _picker() {
    Widget chip(EvolutionSeries s) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            key: ValueKey('evolution-${s.id}'),
            label: Text(s.label),
            selected: _series.id == s.id,
            onSelected: (_) => setState(() => _series = s),
            visualDensity: VisualDensity.compact,
          ),
        );
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(const OverallSeries()),
          for (final r in BodyRegion.values) chip(RegionSeries(r)),
          for (final m in Muscle.values) chip(MuscleSeries(m)),
        ],
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({super.key, required this.line});
  final List<(RankPoint, RankScore)> line;

  @override
  Widget build(BuildContext context) {
    final origin = line.first.$1.date;
    double x(DateTime d) => d.difference(origin).inHours / 24;
    final values = [for (final (_, s) in line) s.value];
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    // Whole tiers around the line, at least two, so the bands read as a ladder.
    final minY = (lo / 3).floorToDouble() * 3;
    var maxY = ((hi + 0.01) / 3).ceilToDouble() * 3;
    if (maxY - minY < 6) maxY = minY + 6;
    final maxX = math.max(1.0, x(line.last.$1.date));
    final fmt = DateFormat('d MMM yy');
    final bands = <HorizontalRangeAnnotation>[
      for (final t in Tier.values)
        if (tierBand(t).$2 > minY && tierBand(t).$1 < maxY)
          HorizontalRangeAnnotation(
            y1: math.max(minY, tierBand(t).$1),
            y2: math.min(maxY, tierBand(t).$2),
            color: tierColor(t).withValues(alpha: 0.16),
          ),
    ];
    final spots = [for (final (p, s) in line) FlSpot(x(p.date), s.value)];
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: bands),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: 3,
              getTitlesWidget: (v, meta) {
                final t = RankScore(v + 0.001).tier;
                // One label per tier band, at its middle.
                if ((v - tierBand(t).$1).abs() > 0.01) return const SizedBox.shrink();
                return Text(t.label.substring(0, math.min(4, t.label.length)), style: TextStyle(color: tierColor(t), fontSize: 11, fontWeight: FontWeight.w800));
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: math.max(1.0, maxX / 3),
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(DateFormat('MMM yy').format(origin.add(Duration(hours: (v * 24).round()))),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceHigh,
            getTooltipItems: (touched) => [
              for (final s in touched)
                LineTooltipItem(
                  '${RankScore(s.y).labelWithRr}\n${fmt.format(origin.add(Duration(hours: (s.x * 24).round())))}',
                  const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: spots.length > 2,
            preventCurveOverShooting: true,
            color: Colors.white,
            barWidth: 3,
            dotData: FlDotData(show: spots.length <= 30),
          ),
        ],
      ),
    );
  }
}
