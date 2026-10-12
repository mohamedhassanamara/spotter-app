import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../library/domain/exercise_info.dart';
import '../../tutorials/data/media_repository.dart';
import '../../tutorials/domain/media_matcher.dart';
import '../../tutorials/presentation/exercise_demo.dart';
import '../../workout/data/routine_repository.dart';
import 'edb_v2_review.dart';

final _allMatchesProvider = StreamProvider<List<MediaMatchRow>>((ref) => ref.watch(mediaRepositoryProvider).watchAll());

enum _Filter { routines, unmatched, low }

/// Debug-only: review exercises without a 3D demo or with a low-confidence match, pick the right
/// ExerciseDB animation, and export the picks in `media_overrides.json` format.
class MediaMatchingScreen extends ConsumerStatefulWidget {
  const MediaMatchingScreen({super.key});

  @override
  ConsumerState<MediaMatchingScreen> createState() => _MediaMatchingScreenState();
}

class _MediaMatchingScreenState extends ConsumerState<MediaMatchingScreen> {
  _Filter _filter = _Filter.routines;

  @override
  Widget build(BuildContext context) {
    final matches = ref.watch(_allMatchesProvider).value ?? const [];
    final catalog = ref.watch(catalogProvider).value ?? const <String, ExerciseInfo>{};
    final routines = ref.watch(routinesProvider).value ?? const <RoutineWithExercises>[];
    final routineIds = <String>{for (final r in routines) ...r.exercises.map((e) => e.exerciseId)};
    final byId = {for (final m in matches) m.exerciseId: m};

    bool isLow(MediaMatchRow m) =>
        m.source == 'auto' && m.edbId != null && MediaMatcher.confidenceFor(m.confidence) != MatchConfidence.high;
    bool isUnmatched(MediaMatchRow m) => m.edbId == null;

    final unmatched = matches.where(isUnmatched).length;
    final low = matches.where(isLow).length;
    final rows = matches.where((m) {
      switch (_filter) {
        case _Filter.routines:
          return routineIds.contains(m.exerciseId);
        case _Filter.unmatched:
          return isUnmatched(m);
        case _Filter.low:
          return isLow(m);
      }
    }).toList()
      ..sort((a, b) => (catalog[a.exerciseId]?.name ?? '').compareTo(catalog[b.exerciseId]?.name ?? ''));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Media matching'),
        bottom: const TabBar(tabs: [Tab(text: 'V1 GIFs'), Tab(key: ValueKey('tab-v2'), text: 'V2 videos')]),
        actions: [
          IconButton(
            tooltip: 'Copy overrides JSON',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () async {
              final json = await ref.read(mediaRepositoryProvider).exportOverrides();
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied. Paste into assets/media_overrides.json')),
                );
              }
            },
          ),
        ],
      ),
      body: TabBarView(children: [Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '${matches.length} exercises · ${matches.length - unmatched} with a 3D demo · $unmatched unmatched · $low low confidence',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              for (final f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(switch (f) {
                      _Filter.routines => 'In my routines',
                      _Filter.unmatched => 'Unmatched ($unmatched)',
                      _Filter.low => 'Low confidence ($low)',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: rows.isEmpty
                ? const EmptyState(icon: Icons.check_circle_outline, title: 'Nothing here', message: 'No exercises in this list.')
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = rows[i];
                      final info = catalog[m.exerciseId];
                      final conf = MediaMatcher.confidenceFor(m.confidence);
                      final color = m.edbId == null
                          ? AppColors.danger
                          : (m.source != 'auto' || conf == MatchConfidence.high ? AppColors.primary : AppColors.warning);
                      return ListTile(
                        title: Text(info?.name ?? m.exerciseId, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          m.edbId == null
                              ? 'No demo${m.source == 'auto' ? '' : ' (${m.source})'}'
                              : '${m.edbName} · ${m.source == 'auto' ? '${(m.confidence * 100).round()}%' : m.source}',
                        ),
                        trailing: Icon(Icons.circle, size: 12, color: color),
                        onTap: info == null ? null : () => _pick(context, info, byId[info.id]),
                      );
                    },
                  ),
          ),
        ],
      ), const EdbV2Review()]),
    ),
    );
  }

  Future<void> _pick(BuildContext context, ExerciseInfo info, MediaMatchRow? current) async {
    final matcher = await MediaRepository.matcher();
    final result = matcher.match(MediaRepository.keyFor(info));
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(info.name, style: Theme.of(ctx).textTheme.titleLarge),
          Text('${info.equipment ?? 'no equipment'} · ${info.primaryMuscles.join(', ')}',
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          if (result.candidates.isEmpty) const Text('No candidates share a word with this name.'),
          for (final c in result.candidates)
            _CandidateTile(
              candidate: c,
              selected: current?.edbId == c.edb.id,
              onPick: () async {
                await ref.read(mediaRepositoryProvider).setManual(info.id, c.edb, now: DateTime.now());
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(mediaRepositoryProvider).setManual(info.id, null, now: DateTime.now());
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            icon: const Icon(Icons.block_rounded),
            label: const Text('No good demo: use photos'),
          ),
        ],
      ),
    );
  }
}

class _CandidateTile extends ConsumerWidget {
  const _CandidateTile({required this.candidate, required this.selected, required this.onPick});
  final MediaCandidate candidate;
  final bool selected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frames = ref.watch(gifFramesProvider(candidate.edb.gifUrl));
    final c = candidate;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: selected ? AppColors.primary.withValues(alpha: 0.12) : null,
      child: InkWell(
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 84,
                height: 84,
                color: Colors.white,
                child: frames.when(
                  data: (g) => RawImage(image: g.frames[g.frames.length ~/ 2], fit: BoxFit.contain),
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (_, _) => const Icon(Icons.wifi_off_rounded, color: Colors.black38),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.edb.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${c.edb.equipments.join(', ')} · ${c.edb.targets.join(', ')}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      '${(c.score * 100).round()}%: name ${(c.nameScore * 100).round()} · equipment ${(c.equipmentScore * 100).round()} · muscle ${(c.muscleScore * 100).round()}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
