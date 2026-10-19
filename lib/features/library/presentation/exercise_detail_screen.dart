import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/domain/gym.dart';
import '../../../core/domain/muscles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../history/presentation/exercise_history_screen.dart';
import '../../program/domain/program_videos.dart';
import '../../program/presentation/program_video.dart';
import '../../ranks/data/rank_exclusions.dart';
import '../../ranks/domain/ranks.dart';
import '../../ranks/presentation/anatomy_graph.dart';
import '../../ranks/presentation/muscle_sheet.dart';
import '../../ranks/presentation/rank_badge.dart';
import '../../tutorials/presentation/exercise_demo.dart';
import '../domain/exercise_info.dart';
import '../domain/load_kinds.dart';
import '../domain/log_guide.dart';

/// The tabs of the exercise page.
enum ExerciseTab { about, rank, stats, history }

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId, this.initialTab = ExerciseTab.about});

  final String exerciseId;
  final ExerciseTab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return AsyncBody<Map<String, ExerciseInfo>>(
      value: catalog,
      loading: const Scaffold(body: Center(child: CircularProgressIndicator())),
      builder: (all) {
        final info = all[exerciseId];
        if (info == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.help_outline_rounded,
              title: 'Exercise not found',
              message: 'It may have been deleted.',
            ),
          );
        }
        return _DetailView(info: info, initialTab: initialTab);
      },
    );
  }
}


class _DetailView extends ConsumerStatefulWidget {
  const _DetailView({required this.info, required this.initialTab});
  final ExerciseInfo info;
  final ExerciseTab initialTab;

  @override
  ConsumerState<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends ConsumerState<_DetailView> {
  ExerciseInfo get info => widget.info;

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Delete exercise?',
      message: 'Delete "${info.name}"? This cannot be undone.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final deleted = await ref.read(exerciseRepositoryProvider).deleteCustomIfUnused(info.id);
    if (!context.mounted) return;
    if (deleted) {
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This exercise is used in a routine or a logged session, so it can’t be deleted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final freeze = ref.watch(activeFreezesProvider)[info.id];
    final now = ref.watch(clockProvider)();
    return DefaultTabController(
      length: ExerciseTab.values.length,
      initialIndex: widget.initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              iconSize: 28,
              tooltip: info.isFavorite ? 'Remove favorite' : 'Add favorite',
              onPressed: () => ref.read(exerciseRepositoryProvider).setFavorite(info.id, !info.isFavorite),
              icon: Icon(info.isFavorite ? Icons.star_rounded : Icons.star_border_rounded, color: info.isFavorite ? AppColors.warning : null),
            ),
            if (info.isCustom) ...[
              IconButton(tooltip: 'Edit', onPressed: () => context.push(Routes.editExercise(info.id)), icon: const Icon(Icons.edit_rounded)),
              IconButton(tooltip: 'Delete', onPressed: () => _delete(context), icon: const Icon(Icons.delete_outline_rounded)),
            ],
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text(info.name, key: const ValueKey('exercise-title'), style: Theme.of(context).textTheme.headlineSmall)),
          ),
          if (freeze != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: AppCard(
                borderColor: AppColors.danger,
                child: Row(children: [
                  const Icon(Icons.lock_rounded, color: AppColors.danger, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        'Progression frozen · ${FreezeState(until: freeze.until, baseWeight: freeze.baseWeight).daysLeft(now)} day(s) left',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger),
                      ),
                      const SizedBox(height: 4),
                      Text(freeze.reason, style: const TextStyle(color: AppColors.textSecondary)),
                    ]),
                  ),
                ]),
              ),
            ),
          const TabBar(tabs: [
            Tab(key: ValueKey('tab-about'), text: 'About'),
            Tab(key: ValueKey('tab-rank'), text: 'Rank'),
            Tab(key: ValueKey('tab-stats'), text: 'Stats'),
            Tab(key: ValueKey('tab-history'), text: 'History'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _AboutTab(info: info),
              _RankTab(info: info),
              ExerciseStatsTab(exerciseId: info.id),
              ExerciseSessionsTab(exerciseId: info.id),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class _AboutTab extends ConsumerWidget {
  const _AboutTab({required this.info});
  final ExerciseInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final video = ref.watch(programVideosProvider).value?[info.id];
    final primary = info.targets.primary.toList()..sort((a, b) => info.targets.weightFor(b).compareTo(info.targets.weightFor(a)));
    final secondary = info.targets.secondary.toList()..sort((a, b) => info.targets.weightFor(b).compareTo(info.targets.weightFor(a)));
    final equipment = equipmentTiles(info);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        // 1 · The demo, with Jeff's video as a small thumbnail in the corner.
        Stack(children: [
          // The library's thumbnail grows into the demo (the flight shows the thumbnail, not the animated GIF).
          Hero(
            tag: 'ex-hero-${info.id}',
            flightShuttleBuilder: (_, _, direction, fromContext, toContext) {
              final thumb = (direction == HeroFlightDirection.push ? fromContext : toContext).widget as Hero;
              return thumb.child;
            },
            child: KeyedSubtree(key: const ValueKey('exercise-hero'), child: ExerciseDemo(exerciseId: info.id, targets: info.targets)),
          ),
          if (video != null)
            Positioned(
              right: 10,
              top: 10, // the demo's own speed and pause controls sit bottom-right
              child: Material(
                key: const ValueKey('jeff-video-card'),
                color: Colors.black.withValues(alpha: 0.78),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white24)),
                child: InkWell(
                  key: const ValueKey('watch-jeff-corner'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _openVideo(context, video),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.play_circle_fill_rounded, color: AppColors.danger, size: 26),
                      SizedBox(width: 6),
                      Text("Jeff's demo", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        // 2 · How to log
        OutlinedButton.icon(
          key: const ValueKey('how-to-log'),
          onPressed: () => _openLogGuide(context, ref),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('How to log?'),
        ),
        // 3 · Muscles worked
        const SectionHeader('Muscles worked'),
        AppCard(child: ExerciseBodyFigures(targets: info.targets)),
        // 4 · Primary and secondary muscles
        if (primary.isNotEmpty) ...[
          const SectionHeader('Primary muscle'),
          _MuscleTiles(muscles: primary, color: ExerciseBodyFigures.primaryColor),
        ],
        if (secondary.isNotEmpty) ...[
          const SectionHeader('Secondary muscles'),
          _MuscleTiles(muscles: secondary, color: ExerciseBodyFigures.secondaryColor),
        ],
        // 5 · Equipment
        const SectionHeader('Equipment'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final t in equipment)
            Container(
              key: ValueKey('equipment-${t.label}'),
              width: 104,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(Radii.card), border: Border.all(color: AppColors.outline)),
              child: Column(children: [
                Icon(t.icon, size: 30, color: AppColors.textPrimary),
                const SizedBox(height: 8),
                Text(t.label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
        ]),
        // 6 · Instructions
        const SectionHeader('Instructions'),
        _Steps(info: info),
        if (info.credits.isNotEmpty || info.source == 'fedb' || info.source == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_creditLine(info), key: const ValueKey('exercise-credit'), style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
          ),
        // Photos of real people only here, never as a thumbnail or the main demo.
        if (info.imageUrls.isNotEmpty) ...[
          const SectionHeader('Photos'),
          SizedBox(
            key: const ValueKey('photos-section'),
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: info.imageUrls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.white,
                  child: Image.network(info.imageUrls[i], height: 180, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 1)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openVideo(BuildContext context, ProgramVideo video) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.smart_display_rounded, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Jeff Nippard demo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 10),
            ProgramVideoPlayer(video: video),
          ]),
        ),
      );

  Future<void> _openLogGuide(BuildContext context, WidgetRef ref) {
    final gym = ref.read(gymEquipmentProvider).value ?? GymEquipment.defaults;
    final guide = logGuideFor(
      name: info.name,
      equipment: info.equipment,
      assisted: isAssisted(info.id),
      override: gym.typeOverrides[info.id],
      barWeight: gym.barWeight,
      bodyweightLoaded: extraBodyweightExerciseIds.contains(info.id),
    );
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How to log ${info.name}', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 14),
            Text(guide.headline, key: const ValueKey('log-guide-headline'), style: AppType.title.copyWith(color: AppColors.primary)),
            const SizedBox(height: 8),
            Text(guide.detail, key: const ValueKey('log-guide-detail'), style: const TextStyle(fontSize: 15, height: 1.4)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text(guide.includes, key: const ValueKey('log-guide-includes'), style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
            ]),
            const SizedBox(height: 10),
            Text('Load type: ${guide.type.label}${guide.unilateral ? ' · one side at a time' : ''}', style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class _MuscleTiles extends ConsumerWidget {
  const _MuscleTiles({required this.muscles, required this.color});
  final List<Muscle> muscles;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final m in muscles)
        InkWell(
          key: ValueKey('muscle-tile-${m.key}'),
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: () async {
            final summary = await ref.read(ranksProvider.future);
            if (!context.mounted) return;
            await showMuscleSheet(context, group: m, mode: BodyGraphMode.ranks, summary: summary, volume: null);
          },
          child: Container(
            width: 104,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(Radii.card), border: Border.all(color: color.withValues(alpha: 0.7))),
            child: Column(children: [
              MuscleThumbnail(muscle: m, color: color, size: 64),
              const SizedBox(height: 6),
              Text(m.label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
    ]);
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.info});
  final ExerciseInfo info;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (info.instructions.isEmpty)
          const Text('No steps for this exercise.', style: TextStyle(color: AppColors.textSecondary)),
        for (var i = 0; i < info.instructions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.surfaceHigh,
                child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(info.instructions[i], style: const TextStyle(fontSize: 15, height: 1.4))),
            ]),
          ),
        if (info.notes != null && info.notes!.isNotEmpty) ...[
          const SectionHeader('Notes'),
          Text(info.notes!, style: const TextStyle(fontSize: 15, height: 1.4)),
        ],
      ],
    );
  }
}


// ---------------------------------------------------------------------------
// Rank
// ---------------------------------------------------------------------------

class _RankTab extends ConsumerWidget {
  const _RankTab({required this.info});
  final ExerciseInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(ranksProvider).value;
    final all = [...?summary?.exercises, ...?summary?.hidden];
    final rank = all.where((r) => r.exerciseId == info.id).firstOrNull;
    final standards = ref.watch(standardsProvider).value ?? const <StrengthStandard>[];
    final standard = standards.where((s) => s.exerciseIds.contains(info.id)).firstOrNull;
    final counts = !(ref.watch(rankExclusionsProvider).value ?? const <String>{}).contains(info.id);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        if (rank == null)
          AppCard(
            key: const ValueKey('rank-empty'),
            child: Row(children: [
              const RankBadge(score: null, size: BadgeSize.small, width: 52, animate: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Unranked', style: AppType.title),
                  const SizedBox(height: 4),
                  Text(
                    standard == null
                        ? 'This exercise has no strength standard, so it does not get a rank. Its sets still count in your history and PRs.'
                        : 'Ranked as "${standard.name}". Log a working set to place it.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ]),
              ),
            ]),
          )
        else
          _RankCard(rank: rank),
        if (rank != null) ...[
          const SectionHeader('Ladder'),
          AppCard(child: _LadderPosition(score: rank.score)),
        ],
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SwitchListTile(
            key: const ValueKey('count-toward-ranks'),
            title: const Text('Count toward ranks'),
            subtitle: const Text('Off: the sets stay in your history and PRs, but this exercise never affects a rank.'),
            value: counts,
            onChanged: (on) => RankExclusions(ref.read(databaseProvider)).set(info.id, excluded: !on),
          ),
        ),
        if (standard != null && rank != null)
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 4),
            child: Text('Standard: ${standard.name}${standard.perHand ? ' (per side)' : ''}', style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
          ),
      ],
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.rank});
  final ExerciseRank rank;

  @override
  Widget build(BuildContext context) {
    final color = tierColor(rank.score.tier);
    final nextLabel = rank.score.nextLabel;
    final next = rank.nextThresholdKg;
    return AppCard(
      key: const ValueKey('rank-card'),
      child: Row(children: [
        RankBadge(score: rank.score, size: BadgeSize.small, width: 64, animate: false),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rank.score.labelWithRr, style: AppType.title.copyWith(color: color)),
            const SizedBox(height: 8),
            RrBar(progress: rank.score.divisionProgress, color: color, tier: rank.score.tier, height: 8),
            const SizedBox(height: 8),
            Text('Best e1RM ${rank.bestE1rm.toStringAsFixed(1)} kg · ${formatKg(rank.weight)} kg × ${rank.reps}',
                style: AppType.bodyS.copyWith(color: AppColors.textSecondary, fontFeatures: AppType.tabular)),
            if (next != null && nextLabel != null)
              Text('${next.toStringAsFixed(1)} kg e1RM for $nextLabel', style: AppType.bodyS.copyWith(fontSize: 13, color: AppColors.textTertiary, fontFeatures: AppType.tabular)),
          ]),
        ),
      ]),
    );
  }
}

/// The nine tiers as a ladder with the current one lit.
class _LadderPosition extends StatelessWidget {
  const _LadderPosition({required this.score});
  final RankScore score;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (final t in Tier.values)
          Expanded(
            child: Column(children: [
              Container(
                key: ValueKey('ladder-${t.name}'),
                height: t == score.tier ? 14 : 8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: t.index <= score.tier.index ? tierColor(t) : AppColors.outline,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: t == score.tier ? [BoxShadow(color: tierColor(t).withValues(alpha: 0.6), blurRadius: 8)] : null,
                ),
              ),
            ]),
          ),
      ]),
      const SizedBox(height: 10),
      Text('You are ${score.label}${score.tier == Tier.radiant ? '' : ' of ${Tier.values.length} tiers, ${Tier.values.length - 1 - score.tier.index} to go'}',
          style: const TextStyle(color: AppColors.textSecondary)),
    ]);
  }
}

/// "Sources: free-exercise-db (public domain) · wger.de, CC-BY-SA 4.0, author …".
String _creditLine(ExerciseInfo info) {
  final parts = <String>[
    if (info.source == 'fedb' || info.source == null) 'free-exercise-db (public domain)',
    for (final c in info.credits)
      [c['source'], c['license'], if ((c['author'] as String? ?? '').isNotEmpty) c['author']].whereType<String>().join(', '),
  ];
  return 'Sources: ${parts.toSet().join(' · ')}';
}

