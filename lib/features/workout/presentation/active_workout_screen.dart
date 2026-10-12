import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/domain/equipment.dart';
import '../../../core/domain/training.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../library/domain/exercise_info.dart';
import '../data/session_repository.dart';
import '../../tutorials/presentation/form_check_sheet.dart';
import 'rest_timer.dart';
import 'set_editor_sheet.dart';

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  Timer? _clock;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeSessionProvider);
    final catalog = ref.watch(catalogProvider).value ?? const <String, ExerciseInfo>{};
    return active.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$e'))),
      data: (session) {
        if (session == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Workout')),
            body: EmptyState(
              icon: Icons.fitness_center,
              title: _finishing ? 'Saving…' : 'No workout in progress',
              message: 'Start one from Home or the Train tab.',
              action: FilledButton(onPressed: () => context.go(Routes.train), child: const Text('Go to Train')),
            ),
          );
        }
        return _buildActive(context, session, catalog);
      },
    );
  }

  Widget _buildActive(BuildContext context, ActiveSession session, Map<String, ExerciseInfo> catalog) {
    final elapsed = ref.read(clockProvider)().difference(session.session.startedAt);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: Navigator.of(context).canPop() ? 0 : 16,
        title: InkWell(
          onTap: () async {
            final name = await promptText(context, title: 'Workout name', initial: session.session.name);
            if (name != null && name.trim().isNotEmpty) {
              await ref.read(sessionRepositoryProvider).renameSession(session.session.id, name.trim());
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.session.name, overflow: TextOverflow.ellipsis),
              Text(
                '${formatClock(elapsed)} · ${session.completedWorkingSets} working sets',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _finishing ? null : () => _finish(session, catalog),
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              child: _finishing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Finish'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const RestTimerBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          for (var i = 0; i < session.exercises.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExerciseCard(
                key: ValueKey(session.exercises[i].row.id),
                exercise: session.exercises[i],
                info: catalog[session.exercises[i].row.exerciseId],
                index: i,
                count: session.exercises.length,
                onMove: (delta) => _move(session, i, delta),
              ),
            ),
          if (session.exercises.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Empty workout. Add your first exercise.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            ),
          FilledButton.tonalIcon(
            onPressed: () => _addExercise(session),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add exercise'),
          ),
          const SizedBox(height: 12),
          AppCard(
            onTap: () async {
              final notes = await promptText(context, title: 'Session notes', initial: session.session.notes, maxLines: 4);
              if (notes != null) await ref.read(sessionRepositoryProvider).setSessionNotes(session.session.id, notes);
            },
            child: Row(children: [
              const Icon(Icons.sticky_note_2_outlined, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  session.session.notes.isEmpty ? 'Add session notes' : session.session.notes,
                  style: TextStyle(color: session.session.notes.isEmpty ? AppColors.textSecondary : AppColors.textPrimary),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => _discard(session),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Discard workout'),
          ),
        ],
      ),
    );
  }

  Future<void> _move(ActiveSession session, int index, int delta) async {
    final ids = session.exercises.map((e) => e.row.id).toList();
    final target = index + delta;
    if (target < 0 || target >= ids.length) return;
    final id = ids.removeAt(index);
    ids.insert(target, id);
    await ref.read(sessionRepositoryProvider).reorderExercises(ids);
  }

  Future<void> _addExercise(ActiveSession session) async {
    final id = await context.push<String>(Routes.pickExercise);
    if (id == null || !mounted) return;
    final catalog = await ref.read(catalogProvider.future);
    final info = catalog[id];
    if (info == null) return;
    final settings = ref.read(currentSettingsProvider);
    final coach = await ref.read(coachContextBuilderProvider)();
    final range = info.defaultRange(compound: settings.compoundRange, isolation: settings.isolationRange);
    await ref.read(sessionRepositoryProvider).addExercise(
          sessionId: session.session.id,
          info: info,
          range: range,
          targetSets: 3,
          restSeconds: info.isCompound ? settings.defaultRestCompound : settings.defaultRestIsolation,
          targetRir: settings.defaultRir,
          coach: coach,
        );
  }

  Future<void> _discard(ActiveSession session) async {
    final ok = await confirm(context,
        title: 'Discard workout?', message: 'All sets logged in this session will be deleted.', action: 'Discard', destructive: true);
    if (!ok || !mounted) return;
    await ref.read(restTimerProvider).stop();
    await ref.read(sessionRepositoryProvider).discard(session.session.id);
    if (mounted) context.go(Routes.home);
  }

  Future<void> _finish(ActiveSession session, Map<String, ExerciseInfo> catalog) async {
    final done = session.completedWorkingSets;
    if (done == 0) {
      final discard = await confirm(context,
          title: 'No working sets completed',
          message: 'Complete at least one working set to finish, or discard this workout.',
          action: 'Discard',
          destructive: true);
      if (discard) await _discard(session);
      return;
    }
    final pending = session.exercises.expand((e) => e.sets).where((s) => !s.completed).length;
    if (pending > 0) {
      final ok = await confirm(context,
          title: 'Finish workout?',
          message: '$pending set${pending == 1 ? '' : 's'} not completed will be dropped.',
          action: 'Finish');
      if (!ok) return;
    }
    setState(() => _finishing = true);
    try {
      await ref.read(restTimerProvider).stop();
      final summary = await ref.read(finishServiceProvider).finish(
            sessionId: session.session.id,
            now: ref.read(clockProvider)(),
            catalog: catalog,
            settings: ref.read(currentSettingsProvider),
            health: ref.read(healthSourceProvider),
          );
      ref.read(lastSummaryProvider.notifier).set(summary);
      if (mounted) context.pushReplacement(summary.rankUps.isEmpty ? Routes.summary : Routes.rankUp);
    } catch (e) {
      if (mounted) {
        setState(() => _finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not finish: $e')));
      }
    }
  }
}

class _ExerciseCard extends ConsumerStatefulWidget {
  const _ExerciseCard({
    super.key,
    required this.exercise,
    required this.info,
    required this.index,
    required this.count,
    required this.onMove,
  });

  final ActiveExercise exercise;
  final ExerciseInfo? info;
  final int index;
  final int count;
  final ValueChanged<int> onMove;

  @override
  ConsumerState<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<_ExerciseCard> {
  bool _whyOpen = false;

  ActiveExercise get ex => widget.exercise;

  double get _increment => ref.read(currentSettingsProvider).increments.of(widget.info?.equipmentKind ?? EquipmentKind.other);

  @override
  Widget build(BuildContext context) {
    final sug = ex.suggestion;
    final freeze = ref.watch(activeFreezesProvider)[ex.row.exerciseId];
    final now = ref.watch(clockProvider)();
    final name = widget.info?.name ?? ex.row.exerciseId;
    final workingIdx = <int, int>{};
    var n = 0;
    for (final s in ex.sets) {
      if (!s.isWarmup) workingIdx[s.id] = ++n;
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      borderColor: sug?.techniqueDay == true ? AppColors.red.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => context.push(Routes.exercise(ex.row.exerciseId)),
                  child: Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18)),
                ),
              ),
              if (freeze != null)
                Tooltip(
                  message: 'Progression frozen',
                  child: Chip(
                    avatar: const Icon(Icons.lock_rounded, size: 16, color: AppColors.warning),
                    label: Text('${freeze.until.difference(now).inHours ~/ 24 + 1}d', style: const TextStyle(color: AppColors.warning)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              IconButton(
                tooltip: 'Form check',
                iconSize: 26,
                onPressed: () => showFormCheckSheet(context, ex.row.exerciseId),
                icon: const Icon(Icons.info_outline_rounded),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: _menu,
                itemBuilder: (_) => [
                  if (widget.index > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
                  if (widget.index < widget.count - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
                  const PopupMenuItem(value: 'notes', child: Text('Exercise notes')),
                  const PopupMenuItem(value: 'remove', child: Text('Remove exercise')),
                ],
              ),
            ],
          ),
          Text(
            '${ex.range} reps · ${ex.row.targetSets} sets · rest ${formatClock(Duration(seconds: ex.row.restSeconds))}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          if (sug != null) ...[
            const SizedBox(height: 10),
            _SuggestionBanner(suggestion: sug, open: _whyOpen, onToggle: () => setState(() => _whyOpen = !_whyOpen)),
          ],
          if (ex.row.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Text('📝 ${ex.row.notes}', style: const TextStyle(color: AppColors.textSecondary)),
            ),
          const SizedBox(height: 8),
          const _SetHeader(),
          for (final s in ex.sets)
            _SetRow(
              set: s,
              label: s.isWarmup ? 'W' : '${workingIdx[s.id]}',
              onTap: () => _edit(s, workingIdx[s.id] ?? 0),
              onCheck: () => _quickComplete(s, workingIdx[s.id] ?? 0),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => ref.read(sessionRepositoryProvider).addSet(ex),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Set'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => ref.read(sessionRepositoryProvider).addSet(ex, warmup: true),
                  icon: const Icon(Icons.local_fire_department_outlined),
                  label: const Text('Warm-up'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _menu(String v) async {
    final repo = ref.read(sessionRepositoryProvider);
    switch (v) {
      case 'up':
        widget.onMove(-1);
      case 'down':
        widget.onMove(1);
      case 'notes':
        final notes = await promptText(context, title: 'Exercise notes', initial: ex.row.notes, maxLines: 3);
        if (notes != null) await repo.setExerciseNotes(ex.row.id, notes);
      case 'remove':
        final ok = await confirm(context,
            title: 'Remove exercise?', message: 'Its sets in this workout will be deleted.', action: 'Remove', destructive: true);
        if (ok) await repo.removeExercise(ex.row.id);
    }
  }

  Future<void> _quickComplete(WorkoutSet s, int number) async {
    final repo = ref.read(sessionRepositoryProvider);
    if (s.completed) {
      await repo.uncompleteSet(s.id);
      return;
    }
    if (s.reps <= 0 || repo.wouldOverride(s, s.weight)) {
      // Overrides need an RPE and a reason: go through the sheet.
      return _edit(s, number);
    }
    HapticFeedback.mediumImpact();
    await repo.completeSet(s, weight: s.weight, reps: s.reps, rpe: s.rpe, isWarmup: s.isWarmup, now: ref.read(clockProvider)());
    if (!s.isWarmup) await ref.read(restTimerProvider).start(ex.row.restSeconds);
  }

  Future<void> _edit(WorkoutSet s, int number) async {
    final result = await showSetEditor(
      context,
      set: s,
      increment: _increment,
      exerciseName: widget.info?.name ?? ex.row.exerciseId,
      setNumber: number,
      targetRir: ex.row.targetRir,
    );
    if (result == null || !mounted) return;
    final repo = ref.read(sessionRepositoryProvider);
    switch (result.action) {
      case SetEditAction.complete:
        HapticFeedback.mediumImpact();
        await repo.completeSet(
          s,
          weight: result.weight,
          reps: result.reps,
          rpe: result.rpe,
          isWarmup: result.isWarmup,
          reason: result.reason,
          now: ref.read(clockProvider)(),
        );
        if (!result.isWarmup && !s.completed) await ref.read(restTimerProvider).start(ex.row.restSeconds);
      case SetEditAction.save:
        await repo.updateSet(s.id, weight: result.weight, reps: result.reps, rpe: () => result.rpe, isWarmup: result.isWarmup);
      case SetEditAction.uncomplete:
        await repo.uncompleteSet(s.id);
        await repo.updateSet(s.id, weight: result.weight, reps: result.reps, rpe: () => result.rpe, isWarmup: result.isWarmup);
      case SetEditAction.delete:
        await repo.deleteSet(s);
    }
  }
}

class _SuggestionBanner extends StatelessWidget {
  const _SuggestionBanner({required this.suggestion, required this.open, required this.onToggle});
  final StoredSuggestion suggestion;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final color = suggestion.techniqueDay
        ? AppColors.red
        : suggestion.kind == SuggestionKind.egoFreeze
            ? AppColors.warning
            : suggestion.kind == SuggestionKind.calibration
                ? AppColors.accent
                : AppColors.primary;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  suggestion.kind == SuggestionKind.egoFreeze ? Icons.lock_rounded : Icons.psychology_alt_rounded,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(suggestion.headline, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textSecondary),
              ],
            ),
            if (open) ...[
              const SizedBox(height: 8),
              for (final w in suggestion.why)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ', style: TextStyle(color: AppColors.textSecondary)),
                      Expanded(child: Text(w, style: const TextStyle(color: AppColors.textSecondary, height: 1.3))),
                    ],
                  ),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 2, left: 28),
                child: Text('Why?', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SetHeader extends StatelessWidget {
  const _SetHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700);
    return const Padding(
      padding: EdgeInsets.only(top: 4, bottom: 2, right: 6),
      child: Row(
        children: [
          SizedBox(width: 34, child: Text('SET', style: style)),
          Expanded(flex: 3, child: Text('TARGET', style: style)),
          Expanded(flex: 4, child: Text('KG × REPS', style: style)),
          Expanded(flex: 2, child: Text('RPE', style: style)),
          SizedBox(width: 56),
        ],
      ),
    );
  }
}

/// "BW" for bodyweight-only sets, kg otherwise.
String _load(double kg) => kg == 0 ? 'BW' : formatKg(kg);

class _SetRow extends StatelessWidget {
  const _SetRow({required this.set, required this.label, required this.onTap, required this.onCheck});
  final WorkoutSet set;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final done = set.completed;
    final target = set.isWarmup
        ? '—'
        : set.suggestedWeight == null
            ? 'ramp'
            : '${_load(set.suggestedWeight!)}×${set.suggestedReps ?? '–'}';
    final rowColor = done
        ? (set.isOverride ? AppColors.warning.withValues(alpha: 0.12) : AppColors.primary.withValues(alpha: 0.1))
        : Colors.transparent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        margin: const EdgeInsets.only(top: 4, right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: rowColor, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: set.isWarmup ? AppColors.warning : AppColors.textPrimary,
                ),
              ),
            ),
            Expanded(flex: 3, child: Text(target, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15))),
            Expanded(
              flex: 4,
              child: Row(children: [
                Flexible(
                  child: Text(
                    '${_load(set.weight)} × ${set.reps}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (set.isOverride) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning)),
              ]),
            ),
            Expanded(
              flex: 2,
              child: Text(
                set.rpe == null ? '–' : formatRpe(set.rpe!),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: (set.rpe ?? 0) >= 9.5 ? AppColors.danger : AppColors.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 52,
              height: 48,
              child: IconButton.filled(
                onPressed: onCheck,
                style: IconButton.styleFrom(
                  backgroundColor: done ? AppColors.primary : AppColors.surfaceHigh,
                  foregroundColor: done ? const Color(0xFF06210F) : AppColors.textSecondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_rounded, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
