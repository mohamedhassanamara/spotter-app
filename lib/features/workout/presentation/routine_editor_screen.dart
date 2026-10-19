import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/domain/training.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../library/presentation/exercise_thumb.dart';
import '../../program/data/program_repository.dart';
import '../../program/domain/program.dart';
import '../data/routine_repository.dart';
import 'superset_style.dart';

final _routineProvider = StreamProvider.family<RoutineWithExercises?, int>(
  (ref, id) => ref.watch(routineRepositoryProvider).watchRoutine(id),
);

class RoutineEditorScreen extends ConsumerWidget {
  const RoutineEditorScreen({super.key, required this.routineId});
  final int routineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = ref.watch(_routineProvider(routineId));
    final catalog = ref.watch(catalogProvider).value ?? const {};
    final repo = ref.read(routineRepositoryProvider);
    return AsyncBody(
      value: routine,
      builder: (r) {
        if (r == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.delete_outline, title: 'Routine deleted', message: ''));
        }
        final labels = supersetLabels(r.exercises, id: (e) => e.id, group: (e) => e.supersetGroup);
        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: () async {
                final name = await promptText(context, title: 'Rename routine', initial: r.routine.name);
                if (name != null && name.trim().isNotEmpty) await repo.rename(routineId, name);
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(r.routine.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                const Icon(Icons.edit_rounded, size: 18, color: AppColors.textSecondary),
              ]),
            ),
            actions: [
              IconButton(
                tooltip: 'Delete routine',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  final ok = await confirm(context,
                      title: 'Delete routine?', message: 'Past sessions are kept.', action: 'Delete', destructive: true);
                  if (!ok) return;
                  await repo.delete(routineId);
                  if (context.mounted) context.pop();
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final id = await context.push<String>(Routes.pickExercise);
              final info = id == null ? null : catalog[id] ?? (await ref.read(catalogProvider.future))[id];
              if (info != null) await repo.addExercise(routineId, info, ref.read(currentSettingsProvider));
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Exercise'),
          ),
          body: r.exercises.isEmpty
              ? const EmptyState(
                  icon: Icons.playlist_add_rounded,
                  title: 'Add exercises',
                  message: 'Compounds default to 6–10 reps, isolations to 10–15, with a target of 2 reps in reserve.',
                )
              : ReorderableListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  onReorderItem: (from, to) {
                    final ids = r.exercises.map((e) => e.id).toList();
                    ids.insert(to, ids.removeAt(from));
                    repo.reorder(ids);
                  },
                  children: [
                    for (final (i, e) in r.exercises.indexed)
                      Padding(
                        key: ValueKey(e.id),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          onTap: () => _editTargets(context, ref, e),
                          child: Row(
                            children: [
                              if (labels[e.id] case final l?) ...[
                                Container(
                                  key: ValueKey('routine-superset-${e.id}'),
                                  width: 4,
                                  height: 52,
                                  decoration: BoxDecoration(color: l.color, borderRadius: BorderRadius.circular(2)),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 24,
                                  child: Text(l.label, style: AppType.label.copyWith(color: l.color, letterSpacing: 0)),
                                ),
                              ],
                              if (catalog[e.exerciseId] != null) ...[
                                ExerciseThumb(exercise: catalog[e.exerciseId]!, size: 44, radius: 10),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.displayName ?? catalog[e.exerciseId]?.name ?? e.exerciseId,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    if (decodeSlots(e.programSlots).isEmpty)
                                      Text(
                                        '${e.targetSets} × ${e.repMin}–${e.repMax} · RIR ${e.targetRir} · rest ${formatClock(Duration(seconds: e.restSeconds))}',
                                        style: const TextStyle(color: AppColors.textSecondary),
                                      )
                                    else
                                      _ProgramRowInfo(row: e),
                                  ],
                                ),
                              ),
                              if (i + 1 < r.exercises.length)
                                IconButton(
                                  key: ValueKey('link-${e.id}'),
                                  tooltip: 'Superset with next',
                                  icon: Icon(
                                    Icons.link_rounded,
                                    color: e.supersetGroup != null && e.supersetGroup == r.exercises[i + 1].supersetGroup
                                        ? labels[e.id]?.color ?? AppColors.accent
                                        : AppColors.textTertiary,
                                  ),
                                  onPressed: () => repo.toggleSupersetWithNext(e, r.exercises[i + 1], r.exercises),
                                ),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => repo.removeExercise(e.id),
                              ),
                              const Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _editTargets(BuildContext context, WidgetRef ref, RoutineExercise e) async {
    if (decodeSlots(e.programSlots).isNotEmpty) return _editProgramRow(context, ref, e);
    var min = e.repMin, max = e.repMax, sets = e.targetSets, rest = e.restSeconds, rir = e.targetRir;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => SafeArea(top: false, child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(e.displayName ?? ref.read(catalogProvider).value?[e.exerciseId]?.name ?? e.exerciseId,
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: StepperField(
                    label: 'Min reps',
                    value: '$min',
                    onMinus: () => setState(() => min = (min - 1).clamp(1, max)),
                    onPlus: () => setState(() => min = (min + 1).clamp(1, max)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StepperField(
                    label: 'Max reps',
                    value: '$max',
                    onMinus: () => setState(() => max = (max - 1).clamp(min, 50)),
                    onPlus: () => setState(() => max = (max + 1).clamp(min, 50)),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: StepperField(
                    label: 'Sets',
                    value: '$sets',
                    onMinus: () => setState(() => sets = (sets - 1).clamp(1, 10)),
                    onPlus: () => setState(() => sets = (sets + 1).clamp(1, 10)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StepperField(
                    label: 'Target RIR',
                    value: '$rir',
                    onMinus: () => setState(() => rir = (rir - 1).clamp(0, 5)),
                    onPlus: () => setState(() => rir = (rir + 1).clamp(0, 5)),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              StepperField(
                label: 'Rest',
                value: formatClock(Duration(seconds: rest)),
                onMinus: () => setState(() => rest = (rest - 15).clamp(15, 900)),
                onPlus: () => setState(() => rest = (rest + 15).clamp(15, 900)),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
            ],
          ),
        )),
      ),
    );
    if (saved == true) {
      await ref.read(routineRepositoryProvider).updateExercise(
            e.id,
            range: RepRange(min, max),
            targetSets: sets,
            restSeconds: rest,
            targetRir: rir,
          );
    }
  }
}

enum _ProgramEdit { save, reset }

/// Program rows: rep range, set count and rest override the program; "Reset to program" clears them.
Future<void> _editProgramRow(BuildContext context, WidgetRef ref, RoutineExercise e) async {
  final program = await ref.read(programProvider.future);
  if (!context.mounted) return;
  final slot = program.slot(decodeSlots(e.programSlots).first);
  final base = slot?.repRange ?? RepRange(e.repMin, e.repMax);
  var min = e.overrideRepMin ?? base.min, max = e.overrideRepMax ?? base.max, sets = e.targetSets, rest = e.restSeconds;
  final action = await showModalBottomSheet<_ProgramEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SafeArea(top: false, child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(e.displayName ?? ref.read(catalogProvider).value?[e.exerciseId]?.name ?? e.exerciseId, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Program: ${slot?.workingSets ?? '–'} × $base reps · rest ${slot?.rest?.text ?? 'none'}',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: StepperField(
                  key: const ValueKey('override-min'),
                  label: 'Min reps',
                  value: '$min',
                  onMinus: () => setState(() => min = (min - 1).clamp(1, max)),
                  onPlus: () => setState(() => min = (min + 1).clamp(1, max)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StepperField(
                  key: const ValueKey('override-max'),
                  label: 'Max reps',
                  value: '$max',
                  onMinus: () => setState(() => max = (max - 1).clamp(min, 50)),
                  onPlus: () => setState(() => max = (max + 1).clamp(min, 50)),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: StepperField(
                  key: const ValueKey('override-sets'),
                  label: 'Working sets',
                  value: '$sets',
                  onMinus: () => setState(() => sets = (sets - 1).clamp(1, 10)),
                  onPlus: () => setState(() => sets = (sets + 1).clamp(1, 10)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StepperField(
                  label: 'Rest',
                  value: formatClock(Duration(seconds: rest)),
                  onMinus: () => setState(() => rest = (rest - 15).clamp(0, 900)),
                  onPlus: () => setState(() => rest = (rest + 15).clamp(0, 900)),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            FilledButton(key: const ValueKey('override-save'), onPressed: () => Navigator.of(ctx).pop(_ProgramEdit.save), child: const Text('Save')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('reset-to-program'),
              onPressed: () => Navigator.of(ctx).pop(_ProgramEdit.reset),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset to program'),
            ),
          ],
        ),
      )),
    ),
  );
  final repo = ref.read(routineRepositoryProvider);
  switch (action) {
    case _ProgramEdit.save:
      final range = RepRange(min, max);
      final keepOverride = e.overrideRepMin != null || range != base;
      await repo.setProgramOverrides(e.id, range: keepOverride ? range : null, targetSets: sets, restSeconds: rest);
    case _ProgramEdit.reset:
      await repo.resetToProgram(e, program);
    case null:
  }
}

/// Prescription from the program for a routine row: per-slot sets × reps, warm-ups, rest, and where
/// the exercise sits in the program (its own exercise, a listed substitution, your swap).
class _ProgramRowInfo extends ConsumerWidget {
  const _ProgramRowInfo({required this.row});
  final RoutineExercise row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program = ref.watch(programProvider).value;
    if (program == null) return const SizedBox.shrink();
    final override = row.overrideRepMin != null && row.overrideRepMax != null ? RepRange(row.overrideRepMin!, row.overrideRepMax!) : null;
    final pres = [
      for (final p in prescribeSets(program: program, slotIds: decodeSlots(row.programSlots), sets: row.targetSets))
        override == null ? p : p.withRange(override),
    ];
    final parts = <String>[];
    for (final p in pres) {
      final label = '${p.repRange.min == p.repRange.max ? p.repRange.min : p.repRange}';
      if (parts.isNotEmpty && parts.last.endsWith('× $label')) {
        final n = int.parse(parts.last.split('×').first.trim()) + 1;
        parts[parts.length - 1] = '$n × $label';
      } else {
        parts.add('1 × $label');
      }
    }
    final first = program.slot(decodeSlots(row.programSlots).first);
    final relation = switch (row.programRelation) {
      'substitution' => 'substitution for ${row.programExercise}',
      'swap' => 'your swap for ${row.programExercise}',
      'extra' => 'not in the program (uses ${first?.exercise} prescription)',
      _ => row.programExercise == null ? 'program' : 'program: ${row.programExercise}',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        '${parts.join(' + ')} reps · warm-up ${first?.warmupSets} · rest ${first?.rest?.text ?? 'none (superset)'}',
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      Text(
        'Effort ${pres.map((p) => p.targetRir == null ? '–' : (p.targetRir == 0 ? 'F' : 'RIR ${p.targetRir}')).join(' / ')}',
        style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.accent),
      ),
      Text(override == null ? relation : '$relation · your rep range $override',
          style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textTertiary)),
    ]);
  }
}
