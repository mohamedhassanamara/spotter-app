import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../ranks/data/rank_exclusions.dart';
import '../../tutorials/data/media_repository.dart';
import '../../tutorials/domain/gif_rule.dart';
import '../../tutorials/presentation/exercise_demo.dart';
import '../data/exercise_audit_repository.dart';
import '../domain/exercise_audit.dart';

final _auditProvider = FutureProvider.autoDispose<List<AuditRow>>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  ref.watch(routinesProvider); // routines changed → recheck
  ref.watch(rankExclusionsProvider);
  await ref.watch(_matchesProvider.future); // a GIF fix → recheck
  return ExerciseAuditRepository(ref.watch(databaseProvider)).load(catalog);
});

final _matchesProvider = StreamProvider.autoDispose<List<MediaMatchRow>>((ref) => ref.watch(mediaRepositoryProvider).watchAll());

enum _Filter { problems, routines, all }

/// Debug-only: every exercise I use with its GIF, where its name comes from and the ranking entry it is scored against, checked against
/// the strict rule (same movement and same equipment, otherwise no GIF). Problems get one-tap fixes.
class ExerciseAuditScreen extends ConsumerStatefulWidget {
  const ExerciseAuditScreen({super.key});

  @override
  ConsumerState<ExerciseAuditScreen> createState() => _ExerciseAuditScreenState();
}

class _ExerciseAuditScreenState extends ConsumerState<ExerciseAuditScreen> {
  _Filter _filter = _Filter.problems;

  @override
  Widget build(BuildContext context) {
    final audit = ref.watch(_auditProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise audit')),
      body: audit.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Audit failed', message: '$e'),
        data: (all) {
          final problems = all.where((r) => r.hasIssue).toList();
          final rows = switch (_filter) {
            _Filter.problems => problems,
            _Filter.routines => all.where((r) => r.inRoutines).toList(),
            _Filter.all => all,
          };
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '${all.length} exercises in use · ${problems.length} to fix · ${all.where((r) => r.isVariant).length} ranked as a variant (kept)',
                key: const ValueKey('audit-summary'),
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
                      key: ValueKey('audit-filter-${f.name}'),
                      label: Text(switch (f) {
                        _Filter.problems => 'To fix (${problems.length})',
                        _Filter.routines => 'In my routines',
                        _Filter.all => 'All (${all.length})',
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
                  ? const EmptyState(icon: Icons.check_circle_outline, title: 'Nothing to fix', message: 'Every GIF and ranking entry matches its exercise.')
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => _AuditTile(row: rows[i], onTap: () => _open(rows[i])),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _open(AuditRow row) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _FixSheet(row: row),
      );
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.row, required this.onTap});
  final AuditRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bad = row.hasIssue;
    return ListTile(
      key: ValueKey('audit-row-${row.exercise.id}'),
      onTap: onTap,
      leading: Icon(bad ? Icons.error_rounded : Icons.check_circle_rounded, color: bad ? AppColors.danger : AppColors.primary),
      title: Text(row.exercise.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      isThreeLine: true,
      subtitle: Text(
        [
          '${row.exercise.equipment ?? 'no equipment'} · name: ${row.nameSource}${row.names.isEmpty ? '' : ' (${row.names.join(', ')})'}',
          'GIF: ${row.gifName ?? 'none'}${row.gif == GifVerdict.ok || row.gif == GifVerdict.noGif ? '' : ' ✗'}',
          'Ranked as: ${row.standardName ?? 'not ranked'}${row.standard == StandardVerdict.mismatch ? ' ✗' : (row.isVariant ? ' (variant)' : '')}',
        ].join('\n'),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _FixSheet extends ConsumerWidget {
  const _FixSheet({required this.row});
  final AuditRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ex = row.exercise;
    final badGif = row.gif == GifVerdict.wrongEquipment || row.gif == GifVerdict.wrongMovement;
    final badRank = row.standard == StandardVerdict.mismatch;
    final media = ref.read(mediaRepositoryProvider);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(ex.name, style: Theme.of(context).textTheme.titleLarge),
        Text('${ex.equipment ?? 'no equipment'} · ${ex.primaryMuscles.join(', ')} · id ${ex.id}', style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        if (row.issues.isEmpty) const Text('Nothing wrong with this one.') else for (final i in row.issues) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $i')),
        const SizedBox(height: 12),
        if (badGif) ...[
          FutureBuilder(
            future: MediaRepository.matcher().then((m) => m.match(MediaRepository.keyFor(ex)).best),
            builder: (context, snap) {
              final best = snap.data;
              return Column(children: [
                if (best != null)
                  FilledButton.icon(
                    key: const ValueKey('audit-fix-best'),
                    onPressed: () async {
                      await media.setManual(ex.id, best.edb, now: DateTime.now());
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text('Use "${best.edb.name}" (same movement, same equipment)'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('audit-fix-no-gif'),
                  onPressed: () async {
                    await media.setManual(ex.id, null, now: DateTime.now());
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('No GIF: show the photos'),
                ),
              ]);
            },
          ),
        ],
        if (badRank) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('audit-fix-unrank'),
            onPressed: () async {
              await RankExclusions(ref.read(databaseProvider)).set(ex.id, excluded: true);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.leaderboard_outlined),
            label: Text('Stop ranking this exercise (it is not "${row.standardName}")'),
          ),
        ],
      ],
    );
  }
}
