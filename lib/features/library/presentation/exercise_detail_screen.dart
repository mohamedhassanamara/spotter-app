import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../tutorials/presentation/exercise_demo.dart';
import '../../tutorials/presentation/tutorial_video.dart';
import '../domain/exercise_info.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final String exerciseId;

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
        return _DetailView(info: info);
      },
    );
  }
}

enum _MediaTab { demo, video, steps }

class _DetailView extends ConsumerStatefulWidget {
  const _DetailView({required this.info});
  final ExerciseInfo info;

  @override
  ConsumerState<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends ConsumerState<_DetailView> {
  _MediaTab? _tab;

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
    final pinned = ref.watch(pinnedVideoProvider(info.id));
    // Default: 3D, or Video when a tutorial is pinned (decided once the pin is known).
    final tab = _tab ?? (pinned.hasValue ? (pinned.value != null ? _MediaTab.video : _MediaTab.demo) : _MediaTab.demo);
    final freeze = ref.watch(activeFreezesProvider)[info.id];
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            iconSize: 28,
            tooltip: info.isFavorite ? 'Remove favorite' : 'Add favorite',
            onPressed: () => ref.read(exerciseRepositoryProvider).setFavorite(info.id, !info.isFavorite),
            icon: Icon(info.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: info.isFavorite ? AppColors.warning : null),
          ),
          if (info.isCustom) ...[
            IconButton(
              tooltip: 'Edit',
              onPressed: () => context.push(Routes.editExercise(info.id)),
              icon: const Icon(Icons.edit_rounded),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: () => _delete(context),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          Text(info.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (info.level != null) _InfoChip(icon: Icons.signal_cellular_alt_rounded, label: _cap(info.level!)),
            _InfoChip(icon: Icons.fitness_center_rounded, label: info.equipment == null ? 'No equipment' : _cap(info.equipment!)),
            if (info.mechanic != null) _InfoChip(icon: Icons.account_tree_rounded, label: _cap(info.mechanic!)),
            if (info.isCustom) const _InfoChip(icon: Icons.edit_note_rounded, label: 'Custom'),
          ]),
          if (freeze != null) ...[
            const SizedBox(height: 16),
            AppCard(
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
          ],
          const SizedBox(height: 16),
          SegmentedButton<_MediaTab>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _MediaTab.demo, label: Text('3D'), icon: Icon(Icons.view_in_ar_rounded)),
              ButtonSegment(value: _MediaTab.video, label: Text('Video'), icon: Icon(Icons.smart_display_rounded)),
              ButtonSegment(value: _MediaTab.steps, label: Text('Steps'), icon: Icon(Icons.format_list_numbered_rounded)),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: 16),
          switch (tab) {
            _MediaTab.demo => ExerciseDemo(exerciseId: info.id, fallbackImages: info.imageUrls),
            _MediaTab.video => TutorialVideoTab(exerciseId: info.id, exerciseName: info.name, searchUri: info.formTutorialUri),
            _MediaTab.steps => _Steps(info: info),
          },
          const SectionHeader('Muscles'),
          _MuscleBlock(info: info),
          _HistorySection(info: info),
        ],
      ),
    );
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 16), label: Text(label));
}

class _MuscleBlock extends StatelessWidget {
  const _MuscleBlock({required this.info});
  final ExerciseInfo info;

  @override
  Widget build(BuildContext context) {
    Widget row(String title, List<String> items, Color color) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in items)
                Chip(
                  label: Text(_cap(m)),
                  backgroundColor: color.withValues(alpha: 0.14),
                  side: BorderSide(color: color.withValues(alpha: 0.6)),
                ),
            ]),
          ]),
        );
    final groups = [
      ...info.targets.primary.map((g) => g.label),
      ...info.targets.secondary.map((g) => '${g.label} (secondary)'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (info.primaryMuscles.isNotEmpty) row('Primary', info.primaryMuscles, AppColors.primary),
      if (info.secondaryMuscles.isNotEmpty) row('Secondary', info.secondaryMuscles, AppColors.accent),
      Text(
        groups.isEmpty ? 'Doesn’t count towards any ranking group.' : 'Ranking groups: ${groups.join(', ')}',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    ]);
  }
}

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.info});
  final ExerciseInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider).value;
    final logs = history?.logsFor(info.id) ?? const [];
    final working = logs.where((l) => l.hasWorkingSets).toList();
    if (working.isEmpty) return const SizedBox.shrink();
    final bwIds = ref.watch(bodyweightLoadedIdsProvider).value ?? const <String>{};
    final bw = bwIds.contains(info.id) ? (ref.watch(latestBodyWeightProvider).value?.kg ?? 0) : 0.0;
    final best = working.fold<double>(0, (m, l) {
      final e = l.bestE1rm(bodyweight: bw, validOnly: true);
      return e > m ? e : m;
    });
    final recent = working.reversed.take(3).toList();
    final fmt = DateFormat('EEE d MMM');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader('Your history'),
      AppCard(
        onTap: () => context.push(Routes.exerciseHistory(info.id)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: StatTile(label: 'Best e1RM', value: '${best.toStringAsFixed(1)} kg', icon: Icons.emoji_events_rounded, color: AppColors.warning)),
            Expanded(child: StatTile(label: 'Sessions', value: '${working.length}', icon: Icons.event_repeat_rounded)),
          ]),
          const SizedBox(height: 14),
          for (final l in recent)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(width: 96, child: Text(fmt.format(l.date), style: const TextStyle(color: AppColors.textSecondary))),
                Expanded(
                  child: Text(
                    l.workingSets.map((s) => '${formatKg(s.weight)}×${s.reps}').join(', '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (l.hasOverrides) const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
              ]),
            ),
          const SizedBox(height: 4),
          const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('Full history & chart', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ]),
        ]),
      ),
    ]);
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
