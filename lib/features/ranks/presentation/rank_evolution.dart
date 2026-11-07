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
  EvolutionRange _range = EvolutionRange.all;

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
          final full = [for (final p in points) if (_series.at(p) != null) (p, _series.at(p)!)];
          final now = ref.watch(clockProvider)();
          final window = windowSamples([for (final (p, s) in full) (date: p.date, value: s.value)], _range, now);
          final line = window.samples;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('RANK EVOLUTION', style: AppType.label.copyWith(color: AppColors.textSecondary))),
              if (full.isNotEmpty)
                Text(full.last.$2.label, key: const ValueKey('evolution-now'), style: AppType.bodyS.copyWith(color: tierColor(full.last.$2.tier), fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 2),
            Text(_series.label, key: const ValueKey('evolution-series'), style: AppType.title),
            const SizedBox(height: 10),
            _rangePicker(),
            const SizedBox(height: 8),
            SizedBox(
              height: 230,
              child: line.length < 2
                  ? Center(
                      child: Text(
                        _range == EvolutionRange.all ? 'Log a few weeks of ranked lifts to draw this.' : 'Not enough ranked lifts in this range yet.',
                        key: const ValueKey('evolution-empty'),
                        textAlign: TextAlign.center,
                        style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
                      ),
                    )
                  : _Chart(key: ValueKey('chart-${_series.id}'), line: line, range: _range, start: window.start, end: now),
            ),
            const SizedBox(height: 10),
            _picker(),
          ]);
        },
      ),
    );
  }

  Widget _rangePicker() {
    return Row(children: [
      for (final r in EvolutionRange.values)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              key: ValueKey('evolution-range-${r.name}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _range = r),
              child: Container(
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _range == r ? AppColors.surfaceTop : null,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _range == r ? AppColors.accent : AppColors.outline),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(r.label,
                      maxLines: 1,
                      style: AppType.bodyS.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: _range == r ? AppColors.textPrimary : AppColors.textSecondary)),
                ),
              ),
            ),
          ),
        ),
    ]);
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

/// Bottom-axis label format and tick spacing (days) for each range.
(DateFormat, double) _axisFor(EvolutionRange r, double spanDays) => switch (r) {
      EvolutionRange.week => (DateFormat('EEE'), 1),
      EvolutionRange.month => (DateFormat('d MMM'), 7),
      EvolutionRange.threeMonths => (DateFormat('d MMM'), 30),
      EvolutionRange.year => (DateFormat('MMM'), 91),
      EvolutionRange.all => (spanDays > 400 ? DateFormat('MMM yy') : DateFormat('d MMM'), math.max(1.0, spanDays / 3)),
    };

/// Left label column: wide enough for the longest tier name ("Platinum", "Olympian") at full length.
const double _labelColumn = 64;
const double _axisHeight = 26;

/// Space kept free on both sides of the plot so the first and last points, their rings and their date labels stay visible and tappable
/// (a tap snaps to the nearest point across the plot's full height, so each point's target is at least 44 pt wide unless neighbours are closer).
const double _plotInset = 24;

class _Chart extends StatefulWidget {
  const _Chart({super.key, required this.line, required this.range, required this.start, required this.end});
  final List<EvolutionSample> line;
  final EvolutionRange range;
  final DateTime start;
  final DateTime end;

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> {
  int? _selected;

  @override
  void didUpdateWidget(_Chart old) {
    super.didUpdateWidget(old);
    if (old.range != widget.range || old.line.length != widget.line.length) _selected = null;
  }

  static const _tipWidth = 150.0;
  static const _tipHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    final line = widget.line, range = widget.range;
    final origin = widget.start;
    double x(DateTime d) => d.difference(origin).inHours / 24;
    final values = [for (final s in line) s.value];
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    // Whole tiers around the line, at least two, so the bands read as a ladder.
    final minY = (lo / 3).floorToDouble() * 3;
    var maxY = ((hi + 0.01) / 3).ceilToDouble() * 3;
    if (maxY - minY < 6) maxY = minY + 6;
    final spanX = math.max(1.0, range == EvolutionRange.all ? x(line.last.date) : x(widget.end));
    final (axisFormat, axisInterval) = _axisFor(range, spanX);
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
    final spots = [for (final p in line) FlSpot(x(p.date), p.value)];
    final selected = _selected != null && _selected! < spots.length ? _selected : null;

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final plotLeft = _labelColumn, plotRight = w, plotTop = 0.0, plotBottom = h - _axisHeight;
      final plotW = math.max(1.0, plotRight - plotLeft);
      // The inset in x units, so the plot is padded on both sides while the date ticks stay on their dates.
      final inset = _plotInset * spanX / math.max(1.0, plotW - 2 * _plotInset);
      final minX = -inset, maxX = spanX + inset;
      Offset pixel(FlSpot s) => Offset(
            plotLeft + (s.x - minX) / (maxX - minX) * plotW,
            plotTop + (1 - (s.y - minY) / (maxY - minY)) * (plotBottom - plotTop),
          );

      /// Taps on the plot snap to the nearest point; anywhere else on the chart (labels, margins) dismisses.
      void onTap(Offset p) {
        final inPlot = p.dx >= plotLeft - _plotInset && p.dx <= plotRight && p.dy >= plotTop && p.dy <= plotBottom + 8;
        if (!inPlot) return setState(() => _selected = null);
        var best = 0;
        var bestD = double.infinity;
        for (var i = 0; i < spots.length; i++) {
          final d = (pixel(spots[i]).dx - p.dx).abs();
          if (d < bestD) {
            bestD = d;
            best = i;
          }
        }
        setState(() => _selected = best);
      }

      Widget? tooltip;
      if (selected != null) {
        final at = pixel(spots[selected]);
        final score = RankScore(line[selected].value);
        final left = (at.dx - _tipWidth / 2).clamp(0.0, math.max(0.0, w - _tipWidth)).toDouble();
        final above = at.dy - _tipHeight - 14;
        final top = above >= 0 ? above : math.min(at.dy + 14, h - _tipHeight);
        tooltip = Positioned(
          left: left,
          top: top,
          width: _tipWidth,
          height: _tipHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {}, // a tap on the tooltip keeps it
            child: Container(
              key: const ValueKey('evolution-tooltip'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.outline)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(fmt.format(line[selected].date), style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textSecondary)),
                Text(score.labelWithRr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
                Text('Score ${score.value.toStringAsFixed(2)}', style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ),
          ),
        );
      }

      return TapRegion(
        onTapOutside: (_) {
          if (_selected != null) setState(() => _selected = null);
        },
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('evolution-plot'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => onTap(d.localPosition),
              child: LineChart(
                LineChartData(
                  minX: minX,
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
                        reservedSize: _labelColumn,
                        interval: 3,
                        getTitlesWidget: (v, meta) {
                          final t = RankScore(v + 0.001).tier;
                          // One label per tier band, at its bottom edge.
                          if ((v - tierBand(t).$1).abs() > 0.01) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(t.label, maxLines: 1, softWrap: false, style: TextStyle(color: tierColor(t), fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: _axisHeight,
                        interval: axisInterval,
                        minIncluded: false,
                        maxIncluded: false,
                        getTitlesWidget: (v, meta) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(axisFormat.format(origin.add(Duration(hours: (v * 24).round()))),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ),
                      ),
                    ),
                  ),
                  lineTouchData: const LineTouchData(enabled: false), // taps are handled above: hover and long-press do nothing
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: spots.length > 2,
                      preventCurveOverShooting: true,
                      color: Colors.white,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, _, bar, index) => index == selected
                            ? FlDotCirclePainter(radius: 6, color: Colors.white, strokeWidth: 3, strokeColor: AppColors.accent)
                            : FlDotCirclePainter(radius: spots.length <= 30 ? 3 : 0, color: Colors.white, strokeWidth: 0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ?tooltip,
        ]),
      );
    });
  }
}
