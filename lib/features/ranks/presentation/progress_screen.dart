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
import '../../gamification/domain/streaks.dart';
import '../../readiness/domain/readiness.dart';
import '../domain/ranks.dart';
import '../domain/body_regions.dart';
import 'anatomy_graph.dart';
import 'muscle_sheet.dart';
import 'rank_badge.dart';

/// Progress tab. Deep-linkable: `/progress?tab=ranks`, `/progress?back=1&mode=volume&group=chest`.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, this.initialTab = 0, this.back = false, this.mode = BodyGraphMode.ranks, this.openGroup});

  final int initialTab;
  final bool back;
  final BodyGraphMode mode;

  /// Opens this muscle's sheet on arrival.
  final MuscleGroup? openGroup;

  static const tabs = ['body', 'ranks', 'lifts', 'history'];

  factory ProgressScreen.fromQuery(Map<String, String> q) => ProgressScreen(
        initialTab: tabs.indexOf(q['tab'] ?? 'body').clamp(0, 3),
        back: q['back'] == '1',
        mode: q['mode'] == 'volume' ? BodyGraphMode.volume : BodyGraphMode.ranks,
        openGroup: q['group'] == null ? null : MuscleGroup.fromName(q['group']!),
      );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      initialIndex: initialTab,
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progress'),
          bottom: const TabBar(
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            tabs: [Tab(text: 'Body'), Tab(text: 'Ranks'), Tab(text: 'Lifts'), Tab(text: 'History')],
          ),
        ),
        body: TabBarView(children: [_BodyTab(back: back, mode: mode, openGroup: openGroup), const _RanksTab(), const _LiftsTab(), const _HistoryTab()]),
      ),
    );
  }
}

/// Label of the division after [s], or null at the very top.
String? nextDivisionLabel(RankScore s) => s.nextLabel;

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
  const _BodyTab({this.back = false, this.mode = BodyGraphMode.ranks, this.openGroup});
  final bool back;
  final BodyGraphMode mode;
  final MuscleGroup? openGroup;

  @override
  ConsumerState<_BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends ConsumerState<_BodyTab> {
  late bool _back = widget.back;
  late BodyGraphMode _mode = widget.mode;
  MuscleGroup? _selected;
  bool _openedDeepLink = false;

  Future<void> _open(MuscleGroup g, RankSummary summary, Map<MuscleGroup, GroupVolume> volume) async {
    setState(() => _selected = g);
    await showMuscleSheet(context, group: g, mode: _mode, summary: summary, volume: volume[g]);
    if (mounted) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final ranks = ref.watch(ranksProvider);
    final bw = ref.watch(latestBodyWeightProvider);
    final volume = ref.watch(groupVolumeProvider);
    return AsyncBody(
      value: ranks,
      builder: (summary) {
        final scores = {for (final g in MuscleGroup.values) g: summary.groups[g]?.score};
        final deepLink = widget.openGroup;
        if (deepLink != null && !_openedDeepLink) {
          _openedDeepLink = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _open(deepLink, summary, volume);
          });
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (bw.hasValue && bw.value == null) ...[const _BodyweightCard(), const SizedBox(height: 12)],
            if (_mode == BodyGraphMode.ranks) _OverallCard(score: summary.overall, rankedGroups: summary.groups.length),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<BodyGraphMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: BodyGraphMode.ranks, label: Text('Ranks'), icon: Icon(Icons.shield_rounded)),
                      ButtonSegment(value: BodyGraphMode.volume, label: Text('Volume'), icon: Icon(Icons.local_fire_department_rounded)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) => setState(() => _mode = v.first),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: _back ? 'Show front' : 'Show back',
                  iconSize: 26,
                  style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                  onPressed: () => setState(() {
                    _back = !_back;
                    _selected = null;
                  }),
                  icon: const Icon(Icons.threesixty_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(_back ? 'BACK' : 'FRONT',
                  style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: AnatomyGraph(
                  back: _back,
                  mode: _mode,
                  scores: scores,
                  volume: volume,
                  selected: _selected,
                  onTap: (g) => _open(g, summary, volume),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _mode == BodyGraphMode.ranks
                    ? 'Tap a muscle to see its rank · grey = unranked'
                    : 'Working sets, last 7 days vs. your 4-week weekly average',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            if (_mode == BodyGraphMode.ranks) const _TierLegend() else const _VolumeLegend(),
          ],
        );
      },
    );
  }
}

class _VolumeLegend extends StatelessWidget {
  const _VolumeLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final l in [VolumeLevel.under, VolumeLevel.low, VolumeLevel.onTrack, VolumeLevel.high, VolumeLevel.new_, VolumeLevel.none])
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: volumeColor(l), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(volumeLabel(l), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
      ],
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
    return GameCard(
      accent: s == null ? null : color,
      glow: s != null,
      child: Row(
        children: [
          RankBadge(score: s, size: BadgeSize.medium, width: 76),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('OVERALL RANK', style: AppType.label.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(s?.label ?? 'Unranked', style: AppType.titleL.copyWith(color: s == null ? AppColors.textSecondary : color)),
                const SizedBox(height: 10),
                if (s == null)
                  Text('Log ranked lifts to place on the ladder.', style: AppType.bodyS.copyWith(color: AppColors.textSecondary))
                else ...[
                  LpBar(progress: s.divisionProgress, color: color, lp: s.lp),
                  const SizedBox(height: 6),
                  Text(
                    next == null ? 'Top of the ladder · $rankedGroups/12 groups' : 'Next: $next · $rankedGroups/12 groups',
                    style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
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
        // Weakest → strongest, so the top of the list is what to work on. Unranked groups first.
        final ranked = summary.groups.values.toList()..sort((a, b) => a.score.value.compareTo(b.score.value));
        final unranked = MuscleGroup.values.where((g) => !summary.groups.containsKey(g)).toList();
        final lifts = [...summary.exercises]..sort((a, b) => a.score.value.compareTo(b.score.value));
        void open(MuscleGroup g) => showMuscleSheet(context, group: g, mode: BodyGraphMode.ranks, summary: summary, volume: null);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (bw.hasValue && bw.value == null) ...[const _BodyweightCard(), const SizedBox(height: 12)],
            _OverallCard(score: summary.overall, rankedGroups: summary.groups.length),
            const SectionLabel('Muscle groups · weakest first'),
            for (final g in unranked) ...[
              _GroupRow(
                title: g.label,
                score: null,
                subtitle: (summary.unrankedHints[g] ?? const []).isEmpty
                    ? 'No ranked lift trains this group'
                    : 'Unranked. Try ${summary.unrankedHints[g]!.take(2).map((s) => s.name).join(' or ')}',
                onTap: () => open(g),
              ),
              const SizedBox(height: 8),
            ],
            for (final g in ranked) ...[
              _GroupRow(
                title: g.group.label,
                score: g.score,
                subtitle: '${g.contributions.length} lift${g.contributions.length == 1 ? '' : 's'}',
                onTap: () => open(g.group),
              ),
              const SizedBox(height: 8),
            ],
            const SectionLabel('Lifts · best e1RM, last 90 days · weakest first'),
            if (lifts.isEmpty)
              GameCard(
                child: Text('No ranked lifts yet. Bench, squat, deadlift, rows, curls and ~25 more count.',
                    style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
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

/// One muscle group: badge, name, division and LP bar.
class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.title, required this.score, required this.subtitle, required this.onTap});
  final String title;
  final RankScore? score;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final color = s == null ? AppColors.unranked : tierColor(s.tier);
    return GameCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          RankBadge(score: s, size: BadgeSize.small, width: 44, animate: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(title,
                        style: AppType.title.copyWith(color: s == null ? AppColors.textSecondary : AppColors.textPrimary)),
                  ),
                  Text(s?.label ?? 'Unranked', style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w700, color: color)),
                ]),
                const SizedBox(height: 6),
                if (s != null) LpBar(progress: s.divisionProgress, color: color, lp: s.lp, height: 8),
                if (s != null) const SizedBox(height: 4),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyS.copyWith(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

class _LiftRankCard extends StatelessWidget {
  const _LiftRankCard({required this.rank});
  final ExerciseRank rank;

  @override
  Widget build(BuildContext context) {
    final next = rank.nextThresholdKg;
    final nextLabel = nextDivisionLabel(rank.score);
    final color = tierColor(rank.score.tier);
    return GameCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RankBadge(score: rank.score, size: BadgeSize.small, width: 44, animate: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rank.standard.name, style: AppType.title),
                const SizedBox(height: 2),
                Text(rank.score.labelWithLp,
                    style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 8),
                LpBar(progress: rank.score.divisionProgress, color: color, height: 8),
                const SizedBox(height: 8),
                Text(
                  'e1RM ${rank.bestE1rm.toStringAsFixed(1)} kg · ×${rank.ratio.toStringAsFixed(2)} BW'
                  '${rank.standard.perHand ? ' (per dumbbell)' : ''}',
                  style: AppType.bodyS.copyWith(color: AppColors.textSecondary, fontFeatures: AppType.tabular),
                ),
                if (next != null && nextLabel != null)
                  Text('${next.toStringAsFixed(1)} kg for $nextLabel',
                      style: AppType.bodyS.copyWith(fontSize: 13, color: AppColors.textTertiary, fontFeatures: AppType.tabular)),
              ],
            ),
          ),
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
