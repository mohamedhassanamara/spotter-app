import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/domain/training.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart';

class _BestSet {
  const _BestSet(this.set, this.date, this.sessionId, this.e1rm);
  final LoggedSet set;
  final DateTime date;
  final int sessionId;
  final double e1rm;
}

/// The numbers behind one exercise: working sessions, best sets by e1RM, the e1RM series.
class _ExerciseNumbers {
  _ExerciseNumbers(this.logs, double bw) {
    for (final l in logs) {
      totalVolume += l.volume;
      final e = l.bestE1rm(bodyweight: bw, validOnly: true);
      if (e > 0) points.add((l.date, e));
      for (final s in l.workingSets) {
        if (s.isValidForRecords) best.add(_BestSet(s, l.date, l.sessionId, s.e1rm(bodyweight: bw)));
      }
    }
    best.sort((a, b) => b.e1rm.compareTo(a.e1rm));
  }
  final List<ExerciseSessionLog> logs;
  final points = <(DateTime, double)>[];
  final best = <_BestSet>[];
  var totalVolume = 0.0;
  List<_BestSet> get top => best.take(5).toList();
  int get egoSets => logs.expand((l) => l.workingSets).where((s) => s.isEgoSet).length;
}

Widget _noHistory() => const EmptyState(
      icon: Icons.show_chart_rounded,
      title: 'No history yet',
      message: 'Log this exercise in a workout to see your e1RM trend, best sets and sessions.',
    );

/// Stats tab: bests, the e1RM chart and the best sets.
class ExerciseStatsTab extends ConsumerWidget {
  const ExerciseStatsTab({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bwIds = ref.watch(bodyweightLoadedIdsProvider).value ?? const <String>{};
    final bw = bwIds.contains(exerciseId) ? (ref.watch(latestBodyWeightProvider).value?.kg ?? 0) : 0.0;
    return AsyncBody(
      value: ref.watch(historyProvider),
      builder: (h) {
        final logs = h.logsFor(exerciseId).where((l) => l.hasWorkingSets).toList();
        if (logs.isEmpty) return _noHistory();
        final n = _ExerciseNumbers(logs, bw);
        final top = n.top;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: StatTile(
                      label: 'Best e1RM',
                      value: top.isEmpty ? '—' : '${top.first.e1rm.toStringAsFixed(1)} kg',
                      icon: Icons.emoji_events_rounded,
                      color: AppColors.warning,
                    ),
                  ),
                  Expanded(child: StatTile(label: 'Sessions', value: '${logs.length}', icon: Icons.event_repeat_rounded)),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: StatTile(
                      label: 'Best set',
                      value: top.isEmpty ? '—' : '${formatKg(top.first.set.weight)}×${top.first.set.reps}',
                      icon: Icons.star_rounded,
                    ),
                  ),
                  Expanded(child: StatTile(label: 'Volume', value: formatVolume(n.totalVolume), icon: Icons.stacked_bar_chart_rounded)),
                ]),
                if (bw > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('e1RM includes your bodyweight (${formatKg(bw)} kg).', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ),
              ]),
            ),
            const SectionHeader('Estimated 1RM'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(8, 20, 20, 8),
              child: SizedBox(height: 220, child: _E1rmChart(points: n.points)),
            ),
            if (n.egoSets > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  '${n.egoSets} ego set${n.egoSets == 1 ? '' : 's'} (heavier than suggested and below the rep range) excluded from the chart, PRs and ranks.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
            const SectionHeader('Best sets'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                for (var i = 0; i < top.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: i == 0 ? AppColors.warning.withValues(alpha: 0.2) : AppColors.surfaceHigh,
                      child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: i == 0 ? AppColors.warning : null)),
                    ),
                    title: Text(
                      '${formatKg(top[i].set.weight)} kg × ${top[i].set.reps}${top[i].set.rpe == null ? '' : ' @ ${formatRpe(top[i].set.rpe!)}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(DateFormat('EEE d MMM y').format(top[i].date)),
                    trailing: Text('${top[i].e1rm.toStringAsFixed(1)} kg', style: const TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => context.push(Routes.session(top[i].sessionId)),
                  ),
              ]),
            ),
          ],
        );
      },
    );
  }
}

/// History tab: every session of the exercise, newest first.
class ExerciseSessionsTab extends ConsumerWidget {
  const ExerciseSessionsTab({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('d MMM');
    return AsyncBody(
      value: ref.watch(historyProvider),
      builder: (h) {
        final logs = h.logsFor(exerciseId).where((l) => l.hasWorkingSets).toList();
        if (logs.isEmpty) return _noHistory();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            for (final l in logs.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  onTap: () => context.push(Routes.session(l.sessionId)),
                  child: Row(children: [
                    SizedBox(width: 64, child: Text(fmt.format(l.date), style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
                    Expanded(
                      child: Text(l.workingSets.map((s) => '${formatKg(s.weight)}×${s.reps}').join(', '), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    if (l.hasBadOverrides)
                      Tooltip(
                        message: 'Contains override sets',
                        child: Icon(Icons.warning_amber_rounded, color: l.hasEgoOverrides ? AppColors.danger : AppColors.warning),
                      ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _E1rmChart extends StatelessWidget {
  const _E1rmChart({required this.points});
  final List<(DateTime, double)> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('No valid sets yet', style: TextStyle(color: AppColors.textSecondary)));
    }
    final origin = points.first.$1;
    double x(DateTime d) => d.difference(origin).inHours / 24;
    final spots = [for (final p in points) FlSpot(x(p.$1), double.parse(p.$2.toStringAsFixed(1)))];
    final minY = spots.map((s) => s.y).reduce(math.min);
    final maxY = spots.map((s) => s.y).reduce(math.max);
    final pad = math.max(2.0, (maxY - minY) * 0.15);
    final maxX = math.max(1.0, spots.last.x);
    final fmt = DateFormat('d MMM');

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: (minY - pad).floorToDouble(),
        maxY: (maxY + pad).ceilToDouble(),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.outline, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => Text(
                meta.formattedValue,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: math.max(1.0, maxX / 4),
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  fmt.format(origin.add(Duration(hours: (v * 24).round()))),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceHigh,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.y.toStringAsFixed(1)} kg\n${fmt.format(origin.add(Duration(hours: (s.x * 24).round())))}',
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
            color: AppColors.primary,
            barWidth: 3,
            dotData: FlDotData(show: spots.length <= 40),
            belowBarData: BarAreaData(show: true, color: AppColors.primary.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }
}
