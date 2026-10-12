import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/domain/equipment.dart';
import '../../../core/domain/training.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../library/domain/exercise_info.dart';
import '../../library/domain/name_resolver.dart';
import '../../program/data/program_repository.dart';
import '../data/session_repository.dart';
import '../../tutorials/presentation/form_check_sheet.dart';
import '../../program/presentation/program_widgets.dart';
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
              Text(session.session.name, overflow: TextOverflow.ellipsis, style: AppType.title.copyWith(fontSize: 20)),
              Row(children: [
                Text(formatClock(elapsed), style: AppType.bodyS.copyWith(fontFamily: AppType.display, color: AppColors.primary, fontWeight: FontWeight.w700)),
                Flexible(
                  child: Text(
                    '  ·  ${session.completedWorkingSets} working sets',
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ]),
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
          OutlinedButton.icon(
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
    } catch (e, st) {
      ErrorLog.instance.recordCaught(e, st);
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
    final name = ex.row.displayName ?? widget.info?.name ?? ex.row.exerciseId;
    final workingIdx = <int, int>{};
    var n = 0;
    for (final s in ex.sets) {
      if (!s.isWarmup) workingIdx[s.id] = ++n;
    }
    final done = ex.sets.where((s) => s.completed && !s.isWarmup).length;
    final total = ex.sets.where((s) => !s.isWarmup).length;

    return GameCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
      accent: sug?.techniqueDay == true ? AppColors.red : (done == total && total > 0 ? AppColors.primary : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => context.push(Routes.exercise(ex.row.exerciseId)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(name, style: AppType.title.copyWith(fontSize: 19)),
                  ),
                ),
              ),
              Text('$done/$total', style: AppType.bodyS.copyWith(fontFamily: AppType.display, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
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
                  const PopupMenuItem(value: 'replace', child: Text('Replace exercise')),
                  const PopupMenuItem(value: 'notes', child: Text('Exercise notes')),
                  const PopupMenuItem(value: 'remove', child: Text('Remove exercise')),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '${ex.range} reps · ${ex.row.targetSets} sets · RIR ${ex.row.targetRir} · rest ${formatClock(Duration(seconds: ex.row.restSeconds))}',
              style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
            ),
          ),
          if (freeze != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GuardrailBanner(
                tone: GuardrailTone.egoFlag,
                title: 'Progression frozen · ${FreezeState(until: freeze.until, baseWeight: freeze.baseWeight).daysLeft(now)} day(s) left',
                details: freeze.reason,
              ),
            ),
          ],
          if (sug != null) ...[
            const SizedBox(height: 10),
            _SuggestionBanner(suggestion: sug, open: _whyOpen, onToggle: () => setState(() => _whyOpen = !_whyOpen)),
          ],
          _ProgramCue(row: ex.row),
          if (ex.row.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Text('📝 ${ex.row.notes}', style: const TextStyle(color: AppColors.textSecondary)),
            ),
          const SizedBox(height: 6),
          for (final s in ex.sets)
            _SetRow(
              key: ValueKey(s.id),
              set: s,
              label: s.isWarmup ? 'W' : '${workingIdx[s.id]}',
              increment: _increment,
              targetRir: ex.row.targetRir,
              onComplete: () => _complete(s, workingIdx[s.id] ?? 0),
              onUndo: () => ref.read(sessionRepositoryProvider).uncompleteSet(s.id),
              onEdit: () => _edit(s, workingIdx[s.id] ?? 0),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ref.read(sessionRepositoryProvider).addSet(ex),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Set'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ref.read(sessionRepositoryProvider).addSet(ex, warmup: true),
                    icon: const Icon(Icons.local_fire_department_outlined),
                    label: const Text('Warm-up'),
                  ),
                ),
              ],
            ),
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
      case 'replace':
        await _replace();
      case 'notes':
        final notes = await promptText(context, title: 'Exercise notes', initial: ex.row.notes, maxLines: 3);
        if (notes != null) await repo.setExerciseNotes(ex.row.id, notes);
      case 'remove':
        final ok = await confirm(context,
            title: 'Remove exercise?', message: 'Its sets in this workout will be deleted.', action: 'Remove', destructive: true);
        if (ok) await repo.removeExercise(ex.row.id);
    }
  }

  /// Program substitutions first (resolved to library exercises), then a library search.
  Future<void> _replace() async {
    final catalog = await ref.read(catalogProvider.future);
    final program = await ref.read(programProvider.future);
    if (!mounted) return;
    final slots = decodeSlots(ex.row.programSlots);
    final slot = slots.isEmpty ? null : program.slot(slots.first);
    final options = <String>[if (slot != null) slot.exercise, ...?slot?.substitutions];
    final resolver = ExerciseNameResolver(catalog.values);
    final resolved = <(String, ExerciseInfo?)>[
      for (final o in options) (o, resolver.resolve(o)?.exercise),
    ];
    if (ex.sets.any((s) => s.completed)) {
      final ok = await confirm(context,
          title: 'Replace exercise?', message: 'Sets already logged on this exercise will be removed.', action: 'Replace', destructive: true);
      if (!ok || !mounted) return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Replace ${ex.row.displayName ?? widget.info?.name ?? ''}', style: AppType.title),
            if (resolved.isNotEmpty) ...[
              const SectionLabel('From the program'),
              for (final (label, info) in resolved)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: info != null && info.id != ex.row.exerciseId,
                  leading: Icon(label == slot?.exercise ? Icons.star_rounded : Icons.swap_horiz_rounded,
                      color: info == null ? AppColors.textTertiary : AppColors.primary),
                  title: Text(label),
                  subtitle: Text(info == null
                      ? 'Not in the library — use search'
                      : (info.id == ex.row.exerciseId ? 'Current exercise' : info.name)),
                  onTap: info == null ? null : () => Navigator.of(ctx).pop(info.id),
                ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(ctx).pop('__search__'),
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search the library'),
            ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final id = picked == '__search__' ? await context.push<String>(Routes.pickExercise) : picked;
    final info = id == null ? null : catalog[id];
    if (info == null || !mounted) return;
    await ref.read(sessionRepositoryProvider).replaceExercise(
          old: ex,
          info: info,
          coach: await ref.read(coachContextBuilderProvider)(),
          program: program,
        );
  }

  /// Swipe or check: complete with the row's values. Overrides go through the sheet (RPE + reason).
  Future<void> _complete(WorkoutSet s, int number) async {
    final repo = ref.read(sessionRepositoryProvider);
    if (s.reps <= 0 || repo.wouldOverride(s, s.weight)) return _edit(s, number);
    HapticFeedback.mediumImpact();
    await repo.completeSet(s, weight: s.weight, reps: s.reps, rpe: s.rpe, isWarmup: s.isWarmup, now: ref.read(clockProvider)());
    if (!s.isWarmup) await ref.read(restTimerProvider).start(ex.row.restSeconds);
  }

  Future<void> _edit(WorkoutSet s, int number) async {
    final result = await showSetEditor(
      context,
      set: s,
      increment: _increment,
      exerciseName: ex.row.displayName ?? widget.info?.name ?? ex.row.exerciseId,
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
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.04)]),
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(suggestion.kind == SuggestionKind.egoFreeze ? Icons.lock_rounded : Icons.psychology_alt_rounded,
                      color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(suggestion.headline, style: AppType.bodyS.copyWith(fontWeight: FontWeight.w800, fontSize: 15))),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textSecondary),
                ],
              ),
              if (open)
                for (final w in suggestion.why)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 28),
                    child: Text('• $w', style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
                  )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 28),
                  child: Text('Why?', style: AppType.label.copyWith(fontSize: 11, color: AppColors.textTertiary)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "BW" for bodyweight-only sets, kg otherwise.
String _load(double kg) => kg == 0 ? 'BW' : formatKg(kg);

/// One set: target on top (muted), actual weight/reps steppers below, RPE chip, swipe right to complete.
class _SetRow extends ConsumerWidget {
  const _SetRow({
    super.key,
    required this.set,
    required this.label,
    required this.increment,
    required this.targetRir,
    required this.onComplete,
    required this.onUndo,
    required this.onEdit,
  });

  final WorkoutSet set;
  final String label;
  final double increment;
  final int targetRir;
  final VoidCallback onComplete;
  final VoidCallback onUndo;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(sessionRepositoryProvider);
    final s = set;
    final overridePct = (!s.isWarmup && s.suggestedWeight != null && s.suggestedWeight! > 0 && repo.wouldOverride(s, s.weight))
        ? ((s.weight - s.suggestedWeight!) / s.suggestedWeight! * 100).round()
        : null;
    final stripe = s.completed
        ? (s.isOverride ? AppColors.warning : AppColors.primary)
        : overridePct != null
            ? AppColors.warning
            : (s.isWarmup ? AppColors.textTertiary : AppColors.outlineBright);
    final reps = (s.targetRepMin != null && s.targetRepMax != null)
        ? (s.targetRepMin == s.targetRepMax ? '${s.targetRepMin}' : '${s.targetRepMin}–${s.targetRepMax}')
        : '${s.suggestedReps ?? '–'}';
    final rir = s.targetRir == null ? '' : ' · ${s.targetRir == 0 ? 'FAILURE' : 'RIR ${s.targetRir}'}';
    final target = s.isWarmup
        ? 'WARM-UP · $reps reps'
        : s.suggestedWeight == null
            ? 'TARGET  ramp up · $reps reps$rir'
            : 'TARGET  ${_load(s.suggestedWeight!)}${s.suggestedWeight == 0 ? '' : ' kg'} × $reps$rir';

    final body = Container(
      margin: const EdgeInsets.only(top: 8, right: 8),
      decoration: BoxDecoration(
        color: s.completed ? stripe.withValues(alpha: 0.09) : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border(left: BorderSide(color: stripe, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.isWarmup ? AppColors.warning.withValues(alpha: 0.16) : AppColors.surfaceTop,
                  shape: BoxShape.circle,
                ),
                child: Text(label,
                    style: AppType.bodyS.copyWith(
                        fontFamily: AppType.display, fontWeight: FontWeight.w800, color: s.isWarmup ? AppColors.warning : AppColors.textPrimary)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(target, style: AppType.label.copyWith(color: AppColors.textSecondary, fontSize: 12))),
              if (overridePct != null || s.isOverride)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(Radii.chip),
                  ),
                  child: Text(
                    overridePct != null ? '+$overridePct% override' : 'override',
                    style: AppType.label.copyWith(color: AppColors.warning, fontSize: 11, letterSpacing: 0.4),
                  ),
                ),
              _RpeChip(set: s, onTap: () => _pickRpe(context, ref)),
            ],
          ),
          if (s.technique != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TechniqueChip(techniqueId: s.technique!),
            ),
          const SizedBox(height: 8),
          if (s.completed)
            Row(children: [
              Expanded(
                child: Text(
                  '${_load(s.weight)}${s.weight == 0 ? '' : ' kg'} × ${s.reps}',
                  style: AppType.number.copyWith(fontSize: 24, color: s.isOverride ? AppColors.warning : AppColors.textPrimary),
                ),
              ),
              _CheckButton(done: true, onTap: onUndo),
            ])
          else
            Row(children: [
              Expanded(
                flex: 6,
                child: StepperBox(
                  dense: true,
                  value: _load(s.weight),
                  unit: s.weight == 0 ? null : 'KG',
                  onMinus: () => repo.updateSet(s.id, weight: (s.weight - increment).clamp(0, 1000).toDouble()),
                  onPlus: () => repo.updateSet(s.id, weight: s.weight + increment),
                  onTapValue: () async {
                    final v = await promptNumber(context, title: 'Weight (kg)', initial: s.weight, suffix: 'kg');
                    if (v != null && v >= 0) await repo.updateSet(s.id, weight: v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 5,
                child: StepperBox(
                  dense: true,
                  value: '${s.reps}',
                  unit: 'REPS',
                  onMinus: () => repo.updateSet(s.id, reps: (s.reps - 1).clamp(0, 100)),
                  onPlus: () => repo.updateSet(s.id, reps: s.reps + 1),
                  onTapValue: () async {
                    final v = await promptNumber(context, title: 'Reps', initial: s.reps.toDouble(), decimal: false);
                    if (v != null && v >= 0) await repo.updateSet(s.id, reps: v.round());
                  },
                ),
              ),
              const SizedBox(width: 6),
              _CheckButton(done: false, onTap: onComplete),
            ]),
        ],
      ),
    );

    return GestureDetector(
      onLongPress: onEdit,
      child: s.completed
          ? body
          : Dismissible(
              key: ValueKey('swipe-${s.id}'),
              direction: DismissDirection.startToEnd,
              dismissThresholds: const {DismissDirection.startToEnd: 0.35},
              confirmDismiss: (_) async {
                onComplete();
                return false; // the row stays; the DB update re-renders it as completed
              },
              background: Container(
                margin: const EdgeInsets.only(top: 8, right: 8),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(Radii.control)),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 20),
                child: const Row(children: [
                  Icon(Icons.check_rounded, color: Color(0xFF06210F), size: 30),
                  SizedBox(width: 8),
                  Text('COMPLETE', style: TextStyle(fontFamily: AppType.display, fontWeight: FontWeight.w800, color: Color(0xFF06210F))),
                ]),
              ),
              child: body,
            ),
    );
  }

  Future<void> _pickRpe(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<double?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('RPE', style: AppType.title),
            Text('Target: stop at $targetRir reps in reserve (RPE ${10 - targetRir})',
                style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in rpeValues)
                ChoiceChip(
                  label: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(formatRpe(v), style: AppType.number.copyWith(fontSize: 18)),
                    Text('RIR ${formatRpe(10 - v)}', style: AppType.label.copyWith(fontSize: 9, letterSpacing: 0.2)),
                  ]),
                  selected: set.rpe == v,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  onSelected: (_) => Navigator.of(ctx).pop(v),
                ),
            ]),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.of(ctx).pop(-1), child: const Text('Clear (counts as RPE 9)')),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    await ref.read(sessionRepositoryProvider).updateSet(set.id, rpe: () => picked < 0 ? null : picked);
  }
}

class _RpeChip extends StatelessWidget {
  const _RpeChip({required this.set, required this.onTap});
  final WorkoutSet set;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rpe = set.rpe;
    final hot = (rpe ?? 0) >= 9.5;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.chip),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36, minWidth: 64),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: hot ? AppColors.danger.withValues(alpha: 0.15) : AppColors.surfaceTop,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: hot ? AppColors.danger.withValues(alpha: 0.6) : AppColors.outlineBright),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(rpe == null ? 'RPE –' : 'RPE ${formatRpe(rpe)}',
              style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w800, color: hot ? AppColors.danger : AppColors.textPrimary)),
          if (rpe != null)
            Text('${formatRpe(10 - rpe)} RIR', style: AppType.label.copyWith(fontSize: 9, letterSpacing: 0.2, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _CheckButton extends StatelessWidget {
  const _CheckButton({required this.done, required this.onTap});
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: IconButton.filled(
        tooltip: done ? 'Mark not done' : 'Complete set',
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: done ? AppColors.primary : AppColors.surfaceTop,
          foregroundColor: done ? const Color(0xFF06210F) : AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
          side: done ? null : const BorderSide(color: AppColors.outlineBright),
        ),
        icon: const Icon(Icons.check_rounded, size: 30),
      ),
    );
  }
}

/// Program week and the program's coaching cue for this exercise.
class _ProgramCue extends ConsumerWidget {
  const _ProgramCue({required this.row});
  final SessionExercise row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = decodeSlots(row.programSlots);
    final program = ref.watch(programProvider).value;
    if (slots.isEmpty || program == null) return const SizedBox.shrink();
    final slot = program.slot(slots.first);
    if (slot == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('MIN-MAX PHASE 2', style: AppType.label.copyWith(fontSize: 10, color: AppColors.accent)),
        if (slot.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(slot.notes, style: AppType.bodyS.copyWith(fontSize: 13, color: AppColors.textSecondary)),
          ),
      ]),
    );
  }
}
