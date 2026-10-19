import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/history.dart';
import '../../../core/domain/muscles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../readiness/domain/readiness.dart';
import '../domain/ranks.dart';
import '../domain/body_regions.dart';
import 'anatomy_graph.dart';
import '../../recovery/domain/recovery.dart';
import 'muscle_sheet.dart';
import 'rank_badge.dart';
import 'rank_evolution.dart';
import 'rank_toggle.dart';

/// Progress tab. Deep-linkable: `/progress?tab=ranks`, `/progress?back=1&mode=volume&group=chest`.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, this.initialTab = 0, this.back = false, this.mode = BodyGraphMode.ranks, this.openGroup});

  final int initialTab;
  final bool back;
  final BodyGraphMode mode;

  /// Opens this muscle's sheet on arrival.
  final Muscle? openGroup;

  static const tabs = ['body', 'ranks', 'lifts', 'history'];

  factory ProgressScreen.fromQuery(Map<String, String> q) => ProgressScreen(
        initialTab: tabs.indexOf(q['tab'] ?? 'body').clamp(0, 3),
        back: q['back'] == '1',
        mode: BodyGraphMode.fromName(q['mode']),
        openGroup: q['group'] == null ? null : Muscle.fromKey(q['group']!),
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
        body: TabBarView(children: [_BodyTab(mode: mode, openGroup: openGroup), const _RanksTab(), const _LiftsTab(), const _HistoryTab()]),
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
  const _BodyTab({this.mode = BodyGraphMode.ranks, this.openGroup});
  final BodyGraphMode mode;
  final Muscle? openGroup;

  @override
  ConsumerState<_BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends ConsumerState<_BodyTab> {
  late BodyGraphMode _mode = widget.mode;
  Muscle? _selected;
  bool _selectedBack = false;
  bool _openedDeepLink = false;

  /// How long the callout shows before the sheet opens.
  static const calloutDelay = Duration(milliseconds: 650);

  @override
  void didUpdateWidget(covariant _BodyTab old) {
    super.didUpdateWidget(old);
    // A deep link (Home recovery card) into an already-open Progress tab switches the mode.
    if (old.mode != widget.mode) _mode = widget.mode;
  }

  Future<void> _open(Muscle g, RankSummary summary, Map<Muscle, GroupVolume> volume, {bool back = false, bool callout = true}) async {
    setState(() {
      _selected = g;
      _selectedBack = back;
    });
    if (callout) {
      await Future<void>.delayed(calloutDelay);
      if (!mounted || _selected != g) return;
    }
    await showMuscleSheet(context, group: g, mode: _mode, summary: summary, volume: volume[g], recovery: ref.read(recoveryProvider)?.of(g));
    if (mounted) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final ranks = ref.watch(ranksProvider);
    final bw = ref.watch(latestBodyWeightProvider);
    final volume = ref.watch(groupVolumeProvider);
    final recovery = ref.watch(recoveryProvider);
    return AsyncBody(
      value: ranks,
      builder: (summary) {
        final scores = {for (final g in Muscle.values) g: summary.muscles[g]?.score};
        final deepLink = widget.openGroup;
        if (deepLink != null && !_openedDeepLink) {
          _openedDeepLink = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _open(deepLink, summary, volume, back: muscleOnBack(deepLink), callout: false);
          });
        }
        final r = recovery?.of(_selected ?? Muscle.biceps);
        final callout = _selected == null
            ? null
            : MuscleCallout(
                muscle: _selected!,
                score: scores[_selected!],
                trailing: switch (_mode) {
                  BodyGraphMode.ranks => scores[_selected!]?.label ?? 'Unranked',
                  BodyGraphMode.recovery => r == null ? null : '${r.pct.round()}%',
                  BodyGraphMode.volume => '${volume[_selected!]?.recentSets ?? 0} sets',
                },
              );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (bw.hasValue && bw.value == null) ...[const _BodyweightCard(), const SizedBox(height: 12)],
            _BodyRankHeader(score: summary.overall),
            const SizedBox(height: 12),
            SegmentedButton<BodyGraphMode>(
              showSelectedIcon: false,
              segments: [
                for (final m in BodyGraphMode.values)
                  ButtonSegment(value: m, label: Text(m.label, key: ValueKey('mode-${m.name}'))),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() {
                _mode = v.first;
                _selected = null;
              }),
            ),
            const SizedBox(height: 14),
            AnatomyGraph(
              mode: _mode,
              scores: scores,
              volume: volume,
              recovery: recovery,
              selected: _selected,
              selectedOnBack: _selectedBack,
              callout: callout,
              onTap: (g, back) => _open(g, summary, volume, back: back),
            ),
            const SizedBox(height: 14),
            switch (_mode) {
              BodyGraphMode.ranks => const _TierLegend(),
              BodyGraphMode.volume => const _VolumeLegend(),
              BodyGraphMode.recovery => const _RecoveryLegend(),
            },
            const SizedBox(height: 8),
            Center(
              child: Text(
                switch (_mode) {
                  BodyGraphMode.ranks => 'Tap a muscle for its rank · grey = unranked',
                  BodyGraphMode.volume => 'Working sets, last 7 days vs. your 4-week weekly average',
                  BodyGraphMode.recovery => 'Estimated from your recent sets and effort · tap a muscle',
                },
                textAlign: TextAlign.center,
                style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textTertiary),
              ),
            ),
            // Liftoff's list under the map: regions with "X/Y ranked", each muscle with its thumbnail.
            if (_mode == BodyGraphMode.ranks) ...[
              const SizedBox(height: 16),
              for (final region in BodyRegion.values) ...[
                _RegionCard(
                  region: summary.regions[region]!,
                  summary: summary,
                  onMuscle: (m) => _open(m, summary, volume, back: muscleOnBack(m), callout: false),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// "BODY RANK · Silver II" with the overall badge.
class _BodyRankHeader extends StatelessWidget {
  const _BodyRankHeader({required this.score});
  final RankScore? score;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final color = s == null ? AppColors.textSecondary : tierColor(s.tier);
    return Row(
      key: const ValueKey('body-rank-header'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RankBadge(score: s, size: BadgeSize.small, width: 40, animate: false),
        const SizedBox(width: 10),
        Text('BODY RANK · ', style: AppType.label.copyWith(fontSize: 14, color: AppColors.textSecondary)),
        Text(s?.label ?? 'Unranked', style: AppType.title.copyWith(color: color)),
      ],
    );
  }
}

class _RecoveryLegend extends StatelessWidget {
  const _RecoveryLegend();

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final (b, range) in [(RecoveryBand.ready, '≥ 90%'), (RecoveryBand.recovering, '60–89%'), (RecoveryBand.fatigued, '< 60%')])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 14, decoration: BoxDecoration(color: recoveryColor(b), borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 6),
              Text('${b.label} $range', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
        ],
      );
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
  const _OverallCard({required this.score, required this.rankedRegions});
  final RankScore? score;
  final int rankedRegions;

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
                    '${next == null ? 'Top of the ladder' : 'Next: $next'} · strength ${s.strength} · $rankedRegions/6 regions',
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
      key: const ValueKey('tier-legend'),
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

class _RanksTab extends ConsumerWidget {
  const _RanksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bw = ref.watch(latestBodyWeightProvider);
    // Off exercises you have logged (everything not in a routine is off by default, so the whole library isn't listed).
    final logged = ref.watch(historyProvider).value?.exerciseIds ?? const <String>{};
    final hidden = {
      for (final id in ref.watch(rankExclusionsProvider).value ?? const <String>{})
        if (logged.contains(id)) id,
    };
    final catalog = ref.watch(catalogProvider).value ?? const {};
    return AsyncBody(
      value: ref.watch(ranksProvider),
      builder: (summary) {
        final lifts = [...summary.exercises]..sort((a, b) => b.score.value.compareTo(a.score.value));
        void open(Muscle m) => showMuscleSheet(context, group: m, mode: BodyGraphMode.ranks, summary: summary, volume: null);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (bw.hasValue && bw.value == null) ...[const _BodyweightCard(), const SizedBox(height: 12)],
            _OverallCard(score: summary.overall, rankedRegions: summary.rankedRegions),
            const SizedBox(height: 10),
            const RankEvolutionCard(),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('open-ladder'),
                onPressed: () => context.push(Routes.ladder),
                icon: const Icon(Icons.stacked_bar_chart_rounded),
                label: const Text('The ladder: every tier and what it takes'),
              ),
            ),
            const SectionLabel('Regions'),
            for (final r in BodyRegion.values) ...[
              _RegionCard(region: summary.regions[r]!, summary: summary, onMuscle: open),
              const SizedBox(height: 10),
            ],
            const SectionLabel('Exercises · best set, last 90 days'),
            if (lifts.isEmpty)
              GameCard(
                child: Text('No ranked exercises yet. Every exercise in your routines and Liftoff history has a standard.',
                    style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
              ),
            for (final r in lifts) ...[
              _LiftRankCard(rank: r),
              const SizedBox(height: 10),
            ],
            if (hidden.isNotEmpty) ...[
              SectionLabel('Hidden from ranks (${hidden.length})'),
              for (final r in summary.hidden) ...[
                _LiftRankCard(rank: r, counted: false),
                const SizedBox(height: 10),
              ],
              // Hidden exercises with nothing logged in the last 90 days.
              for (final id in hidden)
                if (!summary.hidden.any((r) => r.exerciseId == id))
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(catalog[id]?.name ?? id),
                      subtitle: const Text('Records kept · not counted'),
                      trailing: RankToggle(exerciseId: id),
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}

/// A body region: its badge and "X/Y ranked"; expands to its muscles.
class _RegionCard extends StatefulWidget {
  const _RegionCard({required this.region, required this.summary, required this.onMuscle});
  final RegionRank region;
  final RankSummary summary;
  final ValueChanged<Muscle> onMuscle;

  @override
  State<_RegionCard> createState() => _RegionCardState();
}

class _RegionCardState extends State<_RegionCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.region;
    final s = r.score;
    final color = s == null ? AppColors.unranked : tierColor(s.tier);
    return GameCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          InkWell(
            key: ValueKey('region-${r.region.name}'),
            onTap: () => setState(() => _open = !_open),
            child: Row(children: [
              RankBadge(score: s, size: BadgeSize.small, width: 44, animate: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.region.label} · ${r.ranked}/${r.total} ranked', style: AppType.title),
                  const SizedBox(height: 2),
                  Text(
                    s?.label ?? 'Unranked',
                    style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w700, color: color),
                  ),
                  if (s != null) ...[const SizedBox(height: 6), LpBar(progress: s.divisionProgress, color: color, lp: s.lp, height: 8)],
                ]),
              ),
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textSecondary),
            ]),
          ),
          if (_open) ...[
            const SizedBox(height: 8),
            for (final m in r.region.muscles) _MuscleRow(muscle: m, summary: widget.summary, onTap: () => widget.onMuscle(m)),
          ],
        ],
      ),
    );
  }
}

/// One muscle: thumbnail with the muscle highlighted, badge, division and LP.
class _MuscleRow extends StatelessWidget {
  const _MuscleRow({required this.muscle, required this.summary, required this.onTap});
  final Muscle muscle;
  final RankSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rank = summary.muscles[muscle];
    final s = rank?.score;
    final color = s == null ? AppColors.unranked : tierColor(s.tier);
    final hints = summary.unrankedHints[muscle] ?? const [];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          MuscleThumbnail(muscle: muscle, color: s == null ? AppColors.textTertiary : color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(muscle.label, style: AppType.body.copyWith(fontWeight: FontWeight.w700))),
                Text(s == null ? 'Unranked' : '${s.label} · ${s.lp} LP',
                    style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w700, color: color)),
              ]),
              const SizedBox(height: 4),
              if (s != null)
                LpBar(progress: s.divisionProgress, color: color, height: 6)
              else
                Text(
                  hints.isEmpty ? 'None of your exercises trains it as a main muscle' : 'Try ${hints.take(2).map((h) => h.name).join(' or ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textSecondary),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          RankBadge(score: s, size: BadgeSize.small, width: 34, animate: false),
        ]),
      ),
    );
  }
}

class _LiftRankCard extends StatelessWidget {
  const _LiftRankCard({required this.rank, this.counted = true});
  final ExerciseRank rank;
  final bool counted;

  @override
  Widget build(BuildContext context) {
    final next = rank.nextThresholdKg;
    final nextLabel = nextDivisionLabel(rank.score);
    final color = tierColor(rank.score.tier);
    return Opacity(
      key: ValueKey('lift-rank-${rank.exerciseId}'),
      opacity: counted ? 1 : 0.55,
      child: GameCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
      onTap: () => context.push(Routes.exercise(rank.exerciseId)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RankBadge(score: rank.score, size: BadgeSize.small, width: 44, animate: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(rank.name, style: AppType.title)),
                  Text('${rank.strength}', style: AppType.number.copyWith(fontSize: 18, color: color)),
                ]),
                const SizedBox(height: 2),
                Text(rank.score.labelWithLp,
                    style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 8),
                LpBar(progress: rank.score.divisionProgress, color: color, height: 8),
                const SizedBox(height: 8),
                Text(
                  '${liftLine(rank)} · e1RM ${rank.bestE1rm.toStringAsFixed(1)} kg · ×${rank.ratio.toStringAsFixed(2)} BW'
                  '${rank.standard.perHand ? ' (per side)' : ''}',
                  style: AppType.bodyS.copyWith(color: AppColors.textSecondary, fontFeatures: AppType.tabular),
                ),
                if (next != null && nextLabel != null)
                  Text('${next.toStringAsFixed(1)} kg e1RM for $nextLabel',
                      style: AppType.bodyS.copyWith(fontSize: 13, color: AppColors.textTertiary, fontFeatures: AppType.tabular)),
              ],
            ),
          ),
          RankToggle(exerciseId: rank.exerciseId),
        ],
      ),
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
    final today = dateOnly(ref.watch(clockProvider)());
    return AsyncBody(
      value: ref.watch(historyProvider),
      builder: (history) {
        final byDay = <DateTime, List<HistSession>>{};
        for (final s in history.sessions) {
          (byDay[dateOnly(s.startedAt)] ??= []).add(s);
        }
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
                          // Sessions that week (display only; there's no weekly goal).
                          child: Center(
                            child: Text(
                              '${[for (var i = 0; i < 7; i++) ...?byDay[addDays(w, i)]].length}',
                              style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textTertiary),
                            ),
                          ),
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
