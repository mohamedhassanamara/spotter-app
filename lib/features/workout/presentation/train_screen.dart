import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../data/routine_repository.dart';
import 'workout_actions.dart';

class TrainScreen extends ConsumerWidget {
  const TrainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider);
    final active = ref.watch(activeSessionProvider).value;
    final catalog = ref.watch(catalogProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Train')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newRoutine(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Routine'),
      ),
      body: AsyncBody(
        value: routines,
        builder: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (active != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: () => context.push(Routes.workout),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Resume ${active.session.name}'),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: () => startWorkout(context, ref),
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Start empty workout'),
                ),
              ),
            const SectionHeader('Routines'),
            if (list.isEmpty)
              const EmptyState(
                icon: Icons.view_list_rounded,
                title: 'No routines yet',
                message: 'Create a template like "Push A" with ordered exercises, rep ranges, sets and rest.',
              ),
            if (list.isNotEmpty)
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (from, to) {
                  final ids = list.map((r) => r.routine.id).toList();
                  ids.insert(to, ids.removeAt(from));
                  ref.read(routineRepositoryProvider).reorderRoutines(ids);
                },
                children: [
                  for (var i = 0; i < list.length; i++)
                    Padding(
                      key: ValueKey(list[i].routine.id),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RoutineCard(
                        routine: list[i],
                        index: i,
                        names: [for (final e in list[i].exercises) e.displayName ?? catalog[e.exerciseId]?.name ?? e.exerciseId],
                        canStart: active == null,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _newRoutine(BuildContext context, WidgetRef ref) async {
    final name = await promptText(context, title: 'New routine', hint: 'e.g. Push A');
    if (name == null || name.trim().isEmpty) return;
    final id = await ref.read(routineRepositoryProvider).create(name);
    if (context.mounted) context.push(Routes.routine(id));
  }
}

class _RoutineCard extends ConsumerWidget {
  const _RoutineCard({required this.routine, required this.index, required this.names, required this.canStart});
  final RoutineWithExercises routine;
  final int index;
  final List<String> names;
  final bool canStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      onTap: () => context.push(Routes.routine(routine.routine.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.drag_indicator_rounded, color: AppColors.textSecondary),
                ),
              ),
              Expanded(child: Text(routine.routine.name, style: Theme.of(context).textTheme.titleLarge)),
              Text('${names.length} exercises', style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            names.isEmpty ? 'No exercises yet — tap to edit.' : names.join(' · '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: canStart && names.isNotEmpty ? () => startWorkout(context, ref, routine: routine) : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }
}
