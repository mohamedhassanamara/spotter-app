import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/history.dart';
import '../../../core/domain/muscle_group.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart' show formatKg;
import '../../gamification/domain/streaks.dart';
import '../../readiness/domain/readiness.dart';
import '../domain/ranks.dart';
import 'body_graph.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progress'),
          bottom: const TabBar(
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            tabs: [Tab(text: 'Body'), Tab(text: 'Ranks'), Tab(text: 'Lifts'), Tab(text: 'History')],
          ),
        ),
        body: const TabBarView(children: [_BodyTab(), _RanksTab(), _LiftsTab(), _HistoryTab()]),
      ),
    );
  }
}

/// Label of the division after [s], or null at the very top.
String? nextDivisionLabel(RankScore s) {
  final t = s.tier.index, d = s.divisionIndex;
  if (d < 2) return '${s.tier.label} ${const ['III', 'II', 'I'][d + 1]}';
  if (t + 1 < Tier.values.length) return '${Tier.values[t + 1].label} III';
  return null;
}

class _BodyweightCard extends ConsumerWidget {
  const _BodyweightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      borderColor: AppColors.warning,
      onTap: () => enterBodyweight(context, ref),
      child: const Row(
        children: [
          Icon(Icons.monitor_weight_outlined, color: AppColors.warning, size: 32),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bodyweight needed', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(height: 4),
                Text('Ranks compare your e1RM to your bodyweight. No body mass found in Apple Health — tap to enter it.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> enterBodyweight(BuildContext context, WidgetRef ref) async {
  final current = ref.read(latestBodyWeightProvider).value?.kg;
  final kg = await promptNumber(context, title: 'Bodyweight', initial: current, suffix: 'kg');
  if (kg == null || kg < 30 || kg > 300) return;
  await ref.read(bodyWeightRepositoryProvider).addManual(kg);
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _BodyTab extends ConsumerStatefulWidget {
  const _BodyTab();

  @override
  ConsumerState<_BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends ConsumerState<_BodyTab> {
  bool _back = false;
  MuscleGroup? _selected;

  @override
  Widget build(BuildContext context) {
    final ranks = ref.watch(ranksProvider);
    final bw = ref.watch(latestBodyWeightProvider);
    return AsyncBody(
      value: ranks,
      builder: (summary) {
        final scores = {for (final g in MuscleGroup.values) g: summary.groups[g]?.score};
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (bw.hasValue && bw.value == null) ...[const _BodyweightCard(), const SizedBox(height: 12)],
            _OverallCard(score: summary.overall, rankedGroups: summary.groups.length),
            const SizedBox(height: 16),
            Center(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Front'), icon: Icon(Icons.accessibility_new_rounded)),
                  ButtonSegment(value: true, label: Text('Back'), icon: Icon(Icons.flip_rounded)),
                ],
                selected: {_back},
                onSelectionChanged: (v) => setState(() {
                  _back = v.first;
                  _selected = null;
                }),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: BodyGraph(
                  scores: scores,
                  back: _back,
                  selected: _selected,
                  onTap: (g) async {
                    setState(() => _selected = g);
                    await showGroupSheet(context, g, summary, bw.value?.kg ?? 0);
                    if (mounted) setState(() => _selected = null);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text('Tap a muscle to see its rank', style: TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 16),
            const _TierLegend(),
          ],
        );
      },
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.score, required this.rankedGroups});
  final RankScore? score;
  final int rankedGroups;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final color = s == null ? AppColors.unranked : tierColor(s.tier);
    final next = s == null ? null : nextDivisionLabel(s);
    return AppCard(
      borderColor: color.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('OVERALL RANK',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary)),
              ),
              TierBadge(s, large: true),
            ],
          ),
          const SizedBox(height: 14),
          if (s == null)
            const Text('Log ranked lifts to place on the ladder.', style: TextStyle(color: AppColors.textSecondary))
          else ...[
            ProgressBar(value: s.divisionProgress, color: color),
            const SizedBox(height: 8),
            Text(
              next == null
                  ? 'Top of the ladder · $rankedGroups/12 groups ranked'
                  : '${(s.divisionProgress * 100).round()}% to $next · $rankedGroups/12 groups ranked',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _TierLegend extends StatelessWidget {
  const _TierLegend();

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, Color c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 14, height: 14, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        for (final t in Tier.values) chip(t.label, tierColor(t)),
        chip('Unranked', AppColors.unranked),
      ],
    );
  }
}

Future<void> showGroupSheet(BuildContext context, MuscleGroup group, RankSummary summary, double bodyweight) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => _GroupSheet(group: group, summary: summary, bodyweight: bodyweight, controller: scroll),
    ),
  );
}

class _GroupSheet extends StatelessWidget {
  const _GroupSheet({required this.group, required this.summary, required this.bodyweight, required this.controller});
  final MuscleGroup group;
  final RankSummary summary;
  final double bodyweight;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final g = summary.groups[group];
    final title = Text(group.label, style: Theme.of(context).textTheme.headlineSmall);
    if (g == null) {
      final hints = summary.unrankedHints[group] ?? const [];
      return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Row(children: [Expanded(child: title), const TierBadge(null, large: true)]),
          const SizedBox(height: 16),
          Text(
            bodyweight <= 0
                ? 'Enter your bodyweight to unlock ranks.'
                : 'Not ranked yet. Ranks use your best valid e1RM from the last 90 days.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (hints.isNotEmpty) ...[
            const SectionHeader('Log any of these to rank it'),
            for (final s in hints)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_circle_outline, color: AppColors.textSecondary),
                title: Text(s.name),
              ),
          ],
        ],
      );
    }
    final top = g.contributions.first.rank;
    final topNext = top.nextThresholdKg;
    final topNextLabel = nextDivisionLabel(top.score);
    final next = nextDivisionLabel(g.score);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Row(children: [Expanded(child: title), TierBadge(g.score, large: true)]),
        const SizedBox(height: 16),
        ProgressBar(value: g.score.divisionProgress, color: tierColor(g.score.tier)),
        const SizedBox(height: 8),
        Text(
          next == null ? 'Maxed out.' : '${(g.score.divisionProgress * 100).round()}% to $next',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        if (topNext != null && topNextLabel != null) ...[
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(14),
            color: AppColors.surfaceHigh,
            child: Row(
              children: [
                const Icon(Icons.flag_rounded, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Next: e1RM ${formatKg(double.parse(topNext.toStringAsFixed(1)))} kg on ${top.standard.name} for $topNextLabel',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SectionHeader('Contributing lifts'),
        for (final c in g.contributions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.rank.standard.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              'Best e1RM ${c.rank.bestE1rm.toStringAsFixed(1)} kg · ×${c.rank.ratio.toStringAsFixed(2)} BW · '
              '${c.weight >= 1 ? 'primary ×1.0' : 'secondary ×0.3'}',
            ),
            trailing: TierBadge(c.rank.score),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ranks list
// ---------------------------------------------------------------------------

class _RanksTab extends ConsumerWidget {
  const _RanksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bw = ref.watch(latestBodyWeightProvider);
    return AsyncBody(
      value: ref.watch(ranksProvider),
      builder: (summary) {
        final ranked = summary.groups.values.toList()..sort((a, b) => b.score.value.compareTo(a.score.value));
        final unranked = MuscleGroup.values.where((g) => !summary.groups.containsKey(g)).toList();
        final lifts = [...summary.exercises]..sort((a, b) => b.score.value.compareTo(a.score.value));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (bw.hasValue && bw.value == null) ...[const _BodyweightCard(), const SizedBox(height: 12)],
            _OverallCard(score: summary.overall, rankedGroups: summary.groups.length),
            const SectionHeader('Muscle groups'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final g in ranked)
                    ListTile(
                      onTap: () => showGroupSheet(context, g.group, summary, bw.value?.kg ?? 0),
                      leading: _Dot(tierColor(g.score.tier)),
                      title: Text(g.group.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${g.contributions.length} lift${g.contributions.length == 1 ? '' : 's'}'),
                      trailing: TierBadge(g.score),
                    ),
                  for (final g in unranked)
                    ListTile(
                      onTap: () => showGroupSheet(context, g, summary, bw.value?.kg ?? 0),
                      leading: const _Dot(AppColors.unranked),
                      title: Text(g.label, style: const TextStyle(color: AppColors.textSecondary)),
                      subtitle: Text(
                        (summary.unrankedHints[g] ?? const []).isEmpty
                            ? 'No ranked lift for this group'
                            : 'Try: ${summary.unrankedHints[g]!.take(2).map((s) => s.name).join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const TierBadge(null),
                    ),
                ],
              ),
            ),
            const SectionHeader('Lifts (best e1RM, last 90 days)'),
            if (lifts.isEmpty)
              const AppCard(
                child: Text('No ranked lifts yet. Bench, squat, deadlift, rows, curls and ~25 more count.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            for (final r in lifts) ...[
              _LiftRankCard(rank: r),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _LiftRankCard extends StatelessWidget {
  const _LiftRankCard({required this.rank});
  final ExerciseRank rank;

  @override
  Widget build(BuildContext context) {
    final next = rank.nextThresholdKg;
    final nextLabel = nextDivisionLabel(rank.score);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(rank.standard.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              TierBadge(rank.score),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'e1RM ${rank.bestE1rm.toStringAsFixed(1)} kg · ×${rank.ratio.toStringAsFixed(2)} bodyweight'
            '${rank.standard.perHand ? ' (per dumbbell)' : ''}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          ProgressBar(value: rank.score.divisionProgress, color: tierColor(rank.score.tier), height: 8),
          if (next != null && nextLabel != null) ...[
            const SizedBox(height: 6),
            Text('${next.toStringAsFixed(1)} kg for $nextLabel', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lifts
// ---------------------------------------------------------------------------

class _LiftsTab extends ConsumerWidget {
  const _LiftsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).value ?? const {};
    final bwIds = ref.watch(bodyweightLoadedIdsProvider).value ?? const <String>{};
    final bw = ref.watch(latestBodyWeightProvider).value?.kg ?? 0;
    return AsyncBody(
      value: ref.watch(historyProvider),
      builder: (history) {
        final items = <_LiftItem>[];
        history.logsByExercise.forEach((id, logs) {
          final withSets = logs.where((l) => l.hasWorkingSets).toList();
          if (withSets.isEmpty) return;
          final load = bwIds.contains(id) ? bw : 0.0;
          final points = [for (final l in withSets) l.bestE1rm(bodyweight: load, validOnly: true)];
          items.add(_LiftItem(
            id: id,
            name: catalog[id]?.name ?? id,
            last: withSets.last.date,
            sessions: withSets.length,
            points: points,
          ));
        });
        items.sort((a, b) => b.last.compareTo(a.last));
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.show_chart_rounded,
            title: 'No lifts yet',
            message: 'Finish a workout and each exercise gets its own e1RM chart here.',
          );
        }
        final fmt = DateFormat('d MMM');
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final it = items[i];
            final best = it.points.fold<double>(0, math.max);
            return AppCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              onTap: () => context.push(Routes.exerciseHistory(it.id)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          'Last ${fmt.format(it.last)} · ${it.sessions} sessions · best e1RM ${best.toStringAsFixed(1)} kg',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 84, height: 36, child: CustomPaint(painter: SparklinePainter(it.points.length > 12 ? it.points.sublist(it.points.length - 12) : it.points))),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _LiftItem {
  const _LiftItem({required this.id, required this.name, required this.last, required this.sessions, required this.points});
  final String id;
  final String name;
  final DateTime last;
  final int sessions;
  final List<double> points;
}

/// Minimal trend line.
class SparklinePainter extends CustomPainter {
  SparklinePainter(this.values, {this.color = AppColors.primary});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final v = values.where((x) => x > 0).toList();
    if (v.length < 2) {
      if (v.length == 1) {
        canvas.drawCircle(Offset(size.width / 2, size.height / 2), 3, Paint()..color = color);
      }
      return;
    }
    final lo = v.reduce(math.min), hi = v.reduce(math.max);
    final span = (hi - lo) < 1e-6 ? 1.0 : hi - lo;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height - 3 - (size.height - 6) * (v[i] - lo) / span;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    final lastY = size.height - 3 - (size.height - 6) * (v.last - lo) / span;
    canvas.drawCircle(Offset(size.width, lastY), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter old) => old.values != values || old.color != color;
}

// ---------------------------------------------------------------------------
// History calendar
// ---------------------------------------------------------------------------

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  late DateTime _month;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shift(int months) => setState(() {
        _month = DateTime(_month.year, _month.month + months);
        _selected = null;
      });

  @override
  Widget build(BuildContext context) {
    final streak = ref.watch(streakProvider);
    final today = dateOnly(ref.watch(clockProvider)());
    return AsyncBody(
      value: ref.watch(historyProvider),
      builder: (history) {
        final byDay = <DateTime, List<HistSession>>{};
        for (final s in history.sessions) {
          (byDay[dateOnly(s.startedAt)] ??= []).add(s);
        }
        final metWeeks = <DateTime>{
          for (final w in streak?.weeks ?? const <WeekStatus>[]) if (w.met) w.weekStart,
        };
        final monthEnd = DateTime(_month.year, _month.month + 1, 0);
        final rows = <DateTime>[];
        for (var w = weekStart(_month); !w.isAfter(monthEnd); w = addDays(w, 7)) {
          rows.add(w);
        }
        final selected = _selected;
        final listed = selected != null
            ? (byDay[selected] ?? const <HistSession>[])
            : history.sessions
                .where((s) => s.startedAt.year == _month.year && s.startedAt.month == _month.month)
                .toList()
                .reversed
                .toList();
        final monthCount =
            history.sessions.where((s) => s.startedAt.year == _month.year && s.startedAt.month == _month.month).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            AppCard(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(iconSize: 30, onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                      Expanded(
                        child: Column(
                          children: [
                            Text(DateFormat('MMMM yyyy').format(_month),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                            Text('$monthCount session${monthCount == 1 ? '' : 's'}',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                      ),
                      IconButton(iconSize: 30, onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                        Expanded(
                          child: Center(
                            child: Text(d, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      const SizedBox(width: 28, child: Icon(Icons.flag_rounded, size: 14, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final w in rows)
                    Row(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: _DayCell(
                              day: addDays(w, i),
                              inMonth: addDays(w, i).month == _month.month,
                              isToday: addDays(w, i) == today,
                              isSelected: addDays(w, i) == selected,
                              sessions: byDay[addDays(w, i)] ?? const [],
                              onTap: () => setState(() => _selected = addDays(w, i) == selected ? null : addDays(w, i)),
                            ),
                          ),
                        SizedBox(
                          width: 28,
                          child: metWeeks.contains(w)
                              ? const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.green)
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            SectionHeader(
              selected == null ? 'This month' : DateFormat('EEEE d MMMM').format(selected),
              trailing: selected == null
                  ? null
                  : TextButton(onPressed: () => setState(() => _selected = null), child: const Text('Show month')),
            ),
            if (listed.isEmpty)
              const AppCard(child: Text('No sessions.', style: TextStyle(color: AppColors.textSecondary))),
            for (final s in listed) ...[
              _SessionTile(session: s),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

Color _sessionColor(HistSession s) {
  final band = ReadinessBand.fromName(s.readinessBand);
  return band == null ? AppColors.accent : bandColor(band);
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.sessions,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<HistSession> sessions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 50,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceHigh : null,
          borderRadius: BorderRadius.circular(12),
          border: isToday ? Border.all(color: AppColors.primary, width: 1.6) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: sessions.isEmpty ? FontWeight.w500 : FontWeight.w900,
                color: inMonth ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final s in sessions.take(3))
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(color: _sessionColor(s), shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final HistSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: () => context.push(Routes.session(s.id)),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 44,
            decoration: BoxDecoration(color: _sessionColor(s), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('EEE d MMM, HH:mm').format(s.startedAt)} · ${formatDuration(s.duration)} · '
                  '${s.workingSets.length} sets · ${formatVolume(s.volume)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          if (s.hasOverrides) const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
