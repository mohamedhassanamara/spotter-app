import 'dart:math' as math;

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
import '../../coach/data/coach_context.dart' show loadTypeOf;
import '../../coach/domain/guardrail.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../library/domain/exercise_info.dart';
import '../../library/domain/load_kinds.dart';
import '../../library/domain/name_resolver.dart';
import '../../program/data/program_repository.dart';
import '../../settings/presentation/gym_equipment_card.dart' show editLoad;
import '../../tutorials/presentation/form_check_sheet.dart';
import '../../recovery/domain/recovery.dart';
import '../../recovery/presentation/recovery_card.dart' show muscleNames;
import '../data/routine_sync.dart';
import '../data/session_repository.dart';
import '../domain/set_kinds.dart';
import '../domain/superset_rounds.dart';
import 'exercise_block.dart';
import 'keypad.dart';
import '../../coach/domain/praise.dart';
import '../data/history_repository.dart' show loggedSetFromRow;
import '../domain/rest_preview.dart';
import 'rest_timer.dart';
import 'superset_style.dart';

/// The active workout, Liftoff-style: compact set rows, a custom keypad for KG/REPS, rest shown in the
/// header (never full screen), and a minimize button that leaves a mini bar over the tabs.
class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> with WidgetsBindingObserver {
  bool _finishing = false;
  bool _headsUpDismissed = false;

  bool _hideWarmups = false;
  KeypadTarget? _target;
  KeypadBuffer? _buffer;
  final Set<KeypadTarget> _edited = {};
  final Map<KeypadTarget, GlobalKey> _cellKeys = {};
  final _notes = TextEditingController();
  final _notesFocus = FocusNode();
  bool _notesLoaded = false;

  GlobalKey _keyFor(KeypadTarget t) => _cellKeys.putIfAbsent(t, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus) _saveNotes();
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notes.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the gym equipment and history live: the keypad's ±, drop sets and the form-reset offer read
    // the derived grid with `ref.read`, which a provider nobody watches would leave paused on defaults.
    ref.watch(gymEquipmentProvider);
    ref.watch(historyProvider);
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
        if (!_notesLoaded) {
          _notes.text = session.session.notes;
          _notesLoaded = true;
        }
        return _buildActive(context, session, catalog);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  Widget _buildActive(BuildContext context, ActiveSession session, Map<String, ExerciseInfo> catalog) {
    final target = _target;
    ActiveExercise? targetEx;
    if (target != null) {
      targetEx = session.exercises.where((e) => e.sets.any((s) => s.id == target.setId)).firstOrNull;
      if (targetEx == null) {
        // The set disappeared (deleted / exercise removed): close the keypad.
        WidgetsBinding.instance.addPostFrameCallback((_) => _closeKeypad(commit: false));
      }
    }
    final labels = supersetLabels(session.exercises, id: (e) => e.row.id, group: (e) => e.row.supersetGroup);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Minimize workout',
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: _minimize,
        ),
        titleSpacing: 0,
        title: Row(children: [
          Flexible(
            child: InkWell(
              onTap: () => _rename(session),
              child: Text(session.session.name, overflow: TextOverflow.ellipsis, style: AppType.title.copyWith(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 8),
          WorkoutClock(startedAt: session.session.startedAt),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _finishing ? null : () => _finish(session, catalog),
              style: FilledButton.styleFrom(minimumSize: const Size(84, 40)),
              child: _finishing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Finish'),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: ListView(
              // Clear of the home indicator at the end of the list (the keypad's own SafeArea covers it while open).
              padding: EdgeInsets.fromLTRB(10, 4, 10, 32 + (target == null ? MediaQuery.viewPaddingOf(context).bottom : 0)),
              children: [
                if (session.session.routineId != null && !_headsUpDismissed)
                  _FatigueHeadsUp(
                    session: session,
                    catalog: catalog,
                    onDismiss: () => setState(() => _headsUpDismissed = true),
                  ),
                _notesField(),
                for (final e in session.exercises)
                  ExerciseBlock(
                    key: ValueKey('exercise-${e.row.id}'),
                    exercise: e,
                    info: catalog[e.row.exerciseId],
                    ctx: BlockContext(
                      focused: _target,
                      buffer: _buffer,
                      edited: _edited,
                      cellKey: _keyFor,
                      onFocus: (t) => _focus(t),
                      onComplete: (s) => _complete(session, e, s),
                      onCommit: () => _closeKeypad(),
                      onTapOutside: _tapOutsideKeypad,
                      onCopyPrev: _copyPrev,
                      hideWarmups: _hideWarmups,
                      onToggleWarmups: () => setState(() => _hideWarmups = !_hideWarmups),
                      supersetLabel: labels[e.row.id]?.label,
                      supersetRestNote: _supersetRestNote(session, e, labels),
                      supersetColor: labels[e.row.id]?.color,
                      onMenu: (a) => _exerciseMenu(session, e, catalog, a),
                    ),
                  ),
                if (session.exercises.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Empty workout. Add your first exercise.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                  ),
                OutlinedButton.icon(onPressed: () => _addExercise(session), icon: const Icon(Icons.add_rounded), label: const Text('Add exercise')),
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => _discard(session),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Discard workout'),
                ),
              ],
            ),
          ),
        ),
        if (target != null && targetEx != null && _buffer != null)
          WorkoutKeypad(
            field: target.field,
            increment: _increment(catalog[targetEx.row.exerciseId]),
            signToggle: isAssisted(targetEx.row.exerciseId),
            onDigit: (d) => setState(() => _buffer!.digit(d)),
            onDot: () => setState(_buffer!.dot),
            onBackspace: () => setState(_buffer!.backspace),
            onStep: (dir) => setState(() => _buffer!.step(dir,
                increment: _increment(catalog[targetEx!.row.exerciseId]),
                fallback: _cellValue(session, target),
                grid: ref.read(exerciseGridProvider(targetEx.row.exerciseId)))),
            onCopy: () => _copy(session, targetEx!),
            onSign: () => setState(_buffer!.toggleSign),
            onNext: () => _next(session),
            onHide: () => _closeKeypad(),
          ),
      ]),
    );
  }

  Widget _notesField() {
    final open = _notesFocus.hasFocus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        key: const ValueKey('workout-notes'),
        controller: _notes,
        focusNode: _notesFocus,
        minLines: 1,
        maxLines: open ? 4 : 1,
        textCapitalization: TextCapitalization.sentences,
        onTap: () => _closeKeypad(),
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.sticky_note_2_outlined, size: 20),
          hintText: 'Workout notes',
          border: InputBorder.none,
        ),
      ),
    );
  }

  Future<void> _saveNotes() async {
    final session = ref.read(activeSessionProvider).value;
    if (session == null || _notes.text == session.session.notes) return;
    await ref.read(sessionRepositoryProvider).setSessionNotes(session.session.id, _notes.text);
  }

  /// "No rest → A2" for the first of a pair, "Rest 1:00 after the round" on the last.
  String? _supersetRestNote(ActiveSession session, ActiveExercise e, Map<int, ({String label, Color color})> labels) {
    final g = e.row.supersetGroup;
    if (g == null || labels[e.row.id] == null) return null;
    final members = session.exercises.where((x) => x.row.supersetGroup == g).toList();
    final i = members.indexWhere((x) => x.row.id == e.row.id);
    if (i < members.length - 1) return 'No rest → ${labels[members[i + 1].row.id]?.label ?? 'next'}';
    final longest = members.map((x) => x.row.restSeconds).reduce(math.max);
    return 'Rest ${formatClock(Duration(seconds: longest))} after the round ✎';
  }

  double _increment(ExerciseInfo? info) => ref.read(currentSettingsProvider).increments.of(info?.equipmentKind ?? EquipmentKind.other);

  // ---------------------------------------------------------------------------
  // Keypad
  // ---------------------------------------------------------------------------

  WorkoutSet? _setById(ActiveSession session, int id) =>
      session.exercises.expand((e) => e.sets).where((s) => s.id == id).firstOrNull;

  double _cellValue(ActiveSession session, KeypadTarget t) {
    final s = _setById(session, t.setId);
    if (s == null) return 0;
    return t.field == KeypadField.kg ? s.weight : s.reps.toDouble();
  }

  Future<void> _focus(KeypadTarget t) async {
    _pendingTypedSetId = null;
    // A snackbar would sit on top of the keypad's bottom row.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    FocusScope.of(context).unfocus();
    await _commit();
    final session = ref.read(activeSessionProvider).value;
    final assisted = session?.exercises.any((e) => isAssisted(e.row.exerciseId) && e.sets.any((s) => s.id == t.setId)) ?? false;
    setState(() {
      _target = t;
      _buffer = KeypadBuffer(field: t.field, text: assisted && t.field == KeypadField.kg ? '-' : '');
    });
    // Keep the edited cell above the keypad.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keyFor(t).currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, alignment: 0.35, duration: const Duration(milliseconds: 200));
    });
  }

  /// Writes what's typed into the focused cell (nothing when the buffer is empty). Returns the id of
  /// the set that was written, or null when there was nothing typed.
  Future<int?> _commit() async {
    final t = _target, b = _buffer;
    if (t == null || b == null || b.isEmpty) return null;
    final v = b.value;
    if (v == null) return null;
    final repo = ref.read(sessionRepositoryProvider);
    if (t.field == KeypadField.kg) {
      await repo.updateSet(t.setId, weight: v);
      // Pending drop sets under this set follow its new load.
      final session = ref.read(activeSessionProvider).value;
      final ex = session?.exercises.where((e) => e.sets.any((x) => x.id == t.setId)).firstOrNull;
      if (ex != null) {
        await repo.refreshDrops(t.setId,
            increment: _increment(ref.read(catalogProvider).value?[ex.row.exerciseId]), grid: ref.read(exerciseGridProvider(ex.row.exerciseId)));
      }
    } else {
      await repo.updateSet(t.setId, reps: v.round().clamp(0, 999));
    }
    _edited.add(t);
    b.text = '';
    return t.setId;
  }

  /// The app is leaving the foreground (home button, app switcher, lock, a call): save what's typed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _commit();
  }

  /// PREV tap: the previous session's numbers replace the set's, and whatever was typed for it is
  /// discarded (otherwise the stale typed value would overwrite the copy at ✓).
  Future<void> _copyPrev(WorkoutSet s, LoggedSet prev) async {
    if (_target?.setId == s.id) _buffer?.text = '';
    await ref.read(sessionRepositoryProvider).updateSet(s.id, weight: prev.weight, reps: prev.reps);
    _edited
      ..add(KeypadTarget(s.id, KeypadField.kg))
      ..add(KeypadTarget(s.id, KeypadField.reps));
    if (mounted) setState(() {});
  }

  /// A set typed into, then the keypad closed by a tap outside the table: Finish still logs it (typing its numbers
  /// means it was done), just as if the keypad had stayed open.
  int? _pendingTypedSetId;

  Future<void> _tapOutsideKeypad() async {
    final id = await _commit();
    if (id != null) _pendingTypedSetId = id;
    await _closeKeypad(commit: false);
  }

  Future<void> _closeKeypad({bool commit = true}) async {
    if (commit) await _commit();
    if (mounted) {
      setState(() {
        _target = null;
        _buffer = null;
      });
    }
  }

  /// NEXT: KG → REPS → the next set's KG (next exercise after the last set), then close.
  Future<void> _next(ActiveSession session) async {
    final t = _target;
    if (t == null) return;
    await _commit();
    if (t.field == KeypadField.kg) return _focus(KeypadTarget(t.setId, KeypadField.reps));
    final all = [
      for (final s in supersetOrder(session.exercises))
        if (!(_hideWarmups && s.isWarmup)) s,
    ];
    final i = all.indexWhere((s) => s.id == t.setId);
    final next = all.skip(i + 1).where((s) => !s.completed).firstOrNull;
    if (next == null) return _closeKeypad(commit: false);
    return _focus(KeypadTarget(next.id, KeypadField.kg));
  }

  /// Copy: PREV for this set, or the set above when there's no PREV.
  Future<void> _copy(ActiveSession session, ActiveExercise ex) async {
    final t = _target;
    if (t == null) return;
    final history = ref.read(historyProvider).value;
    final prevLog = history?.sessions.reversed.expand((s) => s.exercises).where((e) => e.exerciseId == ex.row.exerciseId).firstOrNull;
    final s = _setById(session, t.setId);
    if (s == null) return;
    double? w;
    int? r;
    final prev = prevLog == null ? null : PrevSets(prevLog.loggedSets).forSet(s, ex.sets);
    if (prev != null) {
      w = prev.weight;
      r = prev.reps;
    } else {
      final i = ex.sets.indexWhere((x) => x.id == s.id);
      if (i > 0) {
        w = ex.sets[i - 1].weight;
        r = ex.sets[i - 1].reps;
      }
    }
    if (w == null || r == null) return;
    await ref.read(sessionRepositoryProvider).updateSet(s.id, weight: w, reps: r);
    _edited
      ..add(KeypadTarget(s.id, KeypadField.kg))
      ..add(KeypadTarget(s.id, KeypadField.reps));
    setState(() => _buffer!.text = '');
  }

  // ---------------------------------------------------------------------------
  // Sets
  // ---------------------------------------------------------------------------

  /// ✓: logs what's in the row (the suggestion when the cells weren't touched), with the effort shown.
  /// The reason sheet appears only for a set that was too heavy: load above the suggestion and reps
  /// below the bottom of the range (section 7).
  Future<void> _complete(ActiveSession session, ActiveExercise ex, WorkoutSet tapped, {bool quiet = false}) async {
    final repo = ref.read(sessionRepositoryProvider);
    if (_target?.setId == tapped.id) {
      await _closeKeypad();
    } else {
      await _commit();
    }
    // Read the set from the database: the session stream can still hold the numbers from before the
    // commit above, and ✓ would log those instead of what was just typed.
    final s = await repo.workoutSet(tapped.id) ?? tapped;
    if (s.completed) return repo.uncompleteSet(s.id);
    final rpe = s.isWarmup || s.kind == SetKind.hold ? null : (s.rpe ?? Effort.fromRir(s.targetRir ?? ex.row.targetRir).rpe);
    OverrideReason? reason;
    if (repo.needsReason(s, weight: s.weight, reps: s.reps, exerciseRepMin: ex.row.repMin)) {
      if (!mounted) return;
      reason = await _askReason(s);
      if (reason == null) return;
    }
    HapticFeedback.lightImpact();
    await repo.completeSet(
      s,
      weight: s.weight,
      reps: s.reps,
      rpe: rpe,
      isWarmup: s.isWarmup,
      reason: reason,
      now: ref.read(clockProvider)(),
      exerciseRepMin: ex.row.repMin,
      restEndedAt: _skippedRestEnd(ex, s),
    );
    if (quiet) return;
    // Missed reps change the later sets of this exercise (and only those).
    await repo.adaptLaterSets(s,
        grid: ref.read(exerciseGridProvider(ex.row.exerciseId)), exerciseRepMin: ex.row.repMin);
    await _maybePraise(session, ex, s.id);
    await _startRest(session, ex, s);
    await _maybeOfferFormReset(ex, s);
  }

  /// When the rest before [s] was skipped, if it was: the previous done set of the exercise is where that rest started.
  DateTime? _skippedRestEnd(ActiveExercise ex, WorkoutSet s) {
    final before = ex.sets.where((x) => x.completed && x.completedAt != null && x.setType == null && x.position < s.position).lastOrNull;
    return before == null ? null : ref.read(restTimerProvider).takeSkip(before.completedAt!);
  }

  /// A good override (heavier than suggested, inside the range at the prescribed effort): a short, varied word of praise,
  /// at most once per exercise and twice per workout.
  Future<void> _maybePraise(ActiveSession session, ActiveExercise ex, int setId) async {
    final row = await ref.read(sessionRepositoryProvider).workoutSet(setId);
    if (row == null || !mounted) return;
    final logged = loggedSetFromRow(row, repMin: ex.row.repMin, repMax: ex.row.repMax, rir: ex.row.targetRir);
    final state = ref.read(praiseProvider)[session.session.id] ?? const PraiseState();
    final message = const PraisePolicy().next(
      set: logged,
      exerciseKey: ex.row.id,
      praisedExercises: state.exercises,
      given: state.count,
      seed: session.session.id,
    );
    if (message == null) return;
    ref.read(praiseProvider.notifier).record(session.session.id, ex.row.id);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('praise-snackbar'),
        duration: const Duration(seconds: 3),
        persist: false,
        content: Row(children: [
          const Icon(Icons.trending_up_rounded, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ]),
      ));
  }

  /// A working set clearly lighter than your recent best (at least one available step) done at the
  /// top of its range looks like a deliberate step down: offer a form reset, once per exercise.
  Future<void> _maybeOfferFormReset(ActiveExercise ex, WorkoutSet s) async {
    if (!s.isWorkingSet || !mounted) return;
    final gym = ref.read(gymRepositoryProvider);
    if ((await gym.formResetOffered()).contains(ex.row.id) || !mounted) return;
    final logs = ref.read(historyProvider).value?.logsFor(ex.row.exerciseId).where((l) => l.hasWorkingSets).toList() ?? const [];
    if (logs.isEmpty) return;
    final recentBest = logs.sublist(math.max(0, logs.length - 3)).map((l) => l.topWeight).reduce(math.max);
    final step = ref.read(exerciseGridProvider(ex.row.exerciseId))?.previous(recentBest);
    final reset = ref.read(formResetsProvider).value?[ex.row.exerciseId];
    final top = s.targetRepMax ?? ex.row.repMax;
    if (step == null || s.weight > step + 0.01 || s.reps < top) return;
    if (reset != null && (reset.weight - s.weight).abs() < 0.01) return;
    await gym.markFormResetOffered(ex.row.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
      key: const ValueKey('form-reset-snackbar'),
      // Gone after 3 s on its own. Flutter keeps a snackbar that has an action on screen forever unless
      // `persist` is false, which is why this one used to stay until dismissed.
      duration: const Duration(seconds: 3),
      persist: false,
      dismissDirection: DismissDirection.horizontal,
      content: Text('${formatKg(s.weight)} kg × ${s.reps}, lighter than your recent ${formatKg(recentBest)} kg. Fixing form?'),
      action: SnackBarAction(label: 'Form reset', onPressed: () => _exerciseMenuById(ex.row.id, 'form-reset')),
    ));
  }

  Future<void> _exerciseMenuById(int sessionExerciseId, String action) async {
    final session = ref.read(activeSessionProvider).value;
    final ex = session?.exercises.where((e) => e.row.id == sessionExerciseId).firstOrNull;
    final catalog = ref.read(catalogProvider).value;
    if (session == null || ex == null || catalog == null) return;
    await _exerciseMenu(session, ex, catalog, action);
  }

  /// Rest after working sets (section 6): none before a drop set or a hold, 5 s before a myo-rep cycle,
  /// and in a superset none until the round is done (one set of each partner), then the longest rest of
  /// the group.
  Future<void> _startRest(ActiveSession session, ActiveExercise ex, WorkoutSet s) async {
    final timer = ref.read(restTimerProvider);
    // Completing a set means the next one started: a rest still running from the one before is over (its
    // Live Activity with it), whether or not this set starts a rest of its own.
    if (s.isWarmup || !ex.row.restEnabled) return timer.stop();
    final idx = ex.sets.indexWhere((x) => x.id == s.id);
    final nextSet = idx >= 0 && idx + 1 < ex.sets.length ? ex.sets[idx + 1] : null;
    if (nextSet != null && nextSet.isFollowUp) {
      return nextSet.kind == SetKind.myo ? timer.start(myoRestSeconds, preview: _restPreview(session, ex, s)) : timer.stop();
    }
    var seconds = ex.row.restSeconds;
    final group = ex.row.supersetGroup;
    if (group != null) {
      final members = session.exercises.where((e) => e.row.supersetGroup == group).toList();
      if (!supersetRoundDone(members, ex.row.id, s.id)) return timer.stop();
      seconds = members.map((e) => e.row.restSeconds).reduce((a, b) => a > b ? a : b);
    }
    await timer.start(seconds, preview: _restPreview(session, ex, s));
  }

  /// The Live Activity's text: the exercise and set that come after this rest.
  RestPreview _restPreview(ActiveSession session, ActiveExercise ex, WorkoutSet done) {
    final catalog = ref.read(catalogProvider).value ?? const {};
    String nameOf(ActiveExercise e) => e.row.displayName ?? catalog[e.row.exerciseId]?.name ?? e.row.exerciseId;
    final next = nextSetAfter(session, ex, done);
    return RestPreview(
      workoutName: session.session.name,
      exerciseName: next == null ? 'Workout' : nameOf(next.exercise),
      nextTarget: next == null ? 'Last set done. Finish when ready' : setTarget(next.exercise, next.set),
    );
  }

  Future<OverrideReason?> _askReason(WorkoutSet s) => showModalBottomSheet<OverrideReason>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Heavier than suggested and short of the range', style: AppType.title),
              const SizedBox(height: 6),
              Text(
                '${formatKg(s.weight)} kg vs ${formatKg(s.suggestedWeight ?? 0)} kg suggested, ${s.reps} reps. '
                'This set won\'t count for ranks or PRs. Why the extra weight?',
                style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              for (final r in OverrideReason.values)
                ListTile(contentPadding: EdgeInsets.zero, title: Text(r.label), onTap: () => Navigator.of(ctx).pop(r)),
            ]),
          ),
        ),
      );

  // ---------------------------------------------------------------------------
  // Exercise menu
  // ---------------------------------------------------------------------------

  Future<void> _exerciseMenu(ActiveSession session, ActiveExercise ex, Map<String, ExerciseInfo> catalog, String action) async {
    await _commit(); // a typed value is never lost to a menu action
    if (!mounted) return;
    final repo = ref.read(sessionRepositoryProvider);
    switch (action) {
      case 'replace':
        await _replace(ex, catalog);
      case 'superset':
        if (ex.row.supersetGroup != null) {
          await repo.leaveSuperset(ex.row.id);
          final rest = session.exercises.where((e) => e.row.supersetGroup == ex.row.supersetGroup && e.row.id != ex.row.id).toList();
          if (rest.length == 1) await repo.leaveSuperset(rest.single.row.id);
          return;
        }
        final others = session.exercises.where((e) => e.row.id != ex.row.id).toList();
        final picked = await showModalBottomSheet<ActiveExercise>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(title: Text('Superset with…')),
              for (final o in others)
                ListTile(
                  title: Text(o.row.displayName ?? catalog[o.row.exerciseId]?.name ?? o.row.exerciseId),
                  onTap: () => Navigator.of(ctx).pop(o),
                ),
            ]),
          ),
        );
        if (picked != null) await repo.superset(ex, picked);
      case 'targets':
        await _targetReps(ex, catalog);
      case 'form-reset':
        await _formReset(ex, catalog);
      case 'weight-steps':
        final info = catalog[ex.row.exerciseId];
        final gymRepo = ref.read(gymRepositoryProvider);
        final g = await gymRepo.load();
        if (!mounted || info == null) return;
        final choice = await editLoad(
          context,
          title: 'Weight steps · ${ex.row.displayName ?? info.name}',
          current: g.typeFor(info.id, loadTypeOf(info)),
          stack: g.stackFor(info.id),
          plate: g.smallestPlate,
          maxLoad: g.maxLoads[info.id],
        );
        if (choice == null) return;
        if (choice.reset) {
          await gymRepo.setStack(info.id, null);
          await gymRepo.setLoadType(info.id, null);
          await gymRepo.setMaxLoad(info.id, null);
        } else {
          await gymRepo.setLoadType(info.id, choice.type);
          await gymRepo.setStack(info.id, choice.stack);
          await gymRepo.setMaxLoad(info.id, choice.maxLoad);
        }
      case 'reorder':
        await _reorderSheet(session, catalog);
      case 'notes':
        final notes = await promptText(context, title: 'Exercise notes', initial: ex.row.notes, maxLines: 3);
        if (notes != null) await repo.setExerciseNotes(ex.row.id, notes);
      case 'howto':
        await showFormCheckSheet(context, ex.row.exerciseId);
      case 'up' || 'down':
        final ids = session.exercises.map((e) => e.row.id).toList();
        final i = ids.indexOf(ex.row.id);
        final j = action == 'up' ? i - 1 : i + 1;
        if (j < 0 || j >= ids.length) return;
        ids
          ..removeAt(i)
          ..insert(j, ex.row.id);
        await repo.reorderExercises(ids);
      case 'remove':
        final ok = await confirm(context, title: 'Remove exercise?', message: 'Its sets in this workout will be deleted.', action: 'Remove', destructive: true);
        if (ok) await repo.removeExercise(ex.row.id);
    }
  }

  /// Target reps for this exercise's working sets, this workout only (offered to the routine at Finish).
  Future<void> _targetReps(ActiveExercise ex, Map<String, ExerciseInfo> catalog) async {
    var min = ex.row.repMin, max = ex.row.repMax;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Target reps · ${ex.row.displayName ?? catalog[ex.row.exerciseId]?.name ?? ''}', style: AppType.title),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: StepperField(
                    key: const ValueKey('target-min'),
                    label: 'Min reps',
                    value: '$min',
                    onMinus: () => setState(() => min = (min - 1).clamp(1, max)),
                    onPlus: () => setState(() => min = (min + 1).clamp(1, max)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StepperField(
                    key: const ValueKey('target-max'),
                    label: 'Max reps',
                    value: '$max',
                    onMinus: () => setState(() => max = (max - 1).clamp(min, 50)),
                    onPlus: () => setState(() => max = (max + 1).clamp(min, 50)),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              FilledButton(key: const ValueKey('target-save'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) await ref.read(sessionRepositoryProvider).setTargetReps(ex, RepRange(min, max));
  }

  /// Form reset: progression restarts from a lighter weight you chose on purpose (e.g. to fix form);
  /// heavier older sessions stop triggering reductions. Refreshes today's suggestion when nothing
  /// is logged on the exercise yet.
  Future<void> _formReset(ActiveExercise ex, Map<String, ExerciseInfo> catalog) async {
    final info = catalog[ex.row.exerciseId];
    final history = ref.read(historyProvider).value;
    final logs = history?.logsFor(ex.row.exerciseId).where((l) => l.hasWorkingSets).toList() ?? const [];
    final initial = ex.suggestion?.formResetHint ?? (logs.isEmpty ? ex.sets.firstOrNull?.weight : logs.last.topWeight) ?? 0;
    final w = await promptNumber(context,
        title: 'Form reset', initial: initial, suffix: 'kg', message: 'Progression restarts from this weight; heavier sessions before it stop counting.');
    if (w == null || info == null || !mounted) return;
    // Date it from the last session at (or under) this weight, so that session is the new base.
    final base = logs.lastWhere((l) => l.topWeight <= w + 0.01, orElse: () => ExerciseSessionLog(sessionId: -1, date: ref.read(clockProvider)(), sets: const []));
    await ref.read(gymRepositoryProvider).setFormReset(ex.row.exerciseId, weight: w, at: base.date);
    if (!ex.sets.any((s) => s.completed)) {
      await ref.read(sessionRepositoryProvider).replaceExercise(
            old: ex,
            info: info,
            coach: await ref.read(workoutCoachProvider)(ex.row.sessionId),
            program: await ref.read(programProvider.future),
          );
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Form reset: progression restarts from ${formatKg(w)} kg')));
  }

  /// Drag to reorder every exercise of the workout at once.
  Future<void> _reorderSheet(ActiveSession session, Map<String, ExerciseInfo> catalog) async {
    final order = [...session.exercises];
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Reorder exercises', style: AppType.title)),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                onReorderItem: (from, to) => setState(() => order.insert(to, order.removeAt(from))),
                children: [
                  for (final (i, e) in order.indexed)
                    ListTile(
                      key: ValueKey('reorder-${e.row.id}'),
                      title: Text(e.row.displayName ?? catalog[e.row.exerciseId]?.name ?? e.row.exerciseId),
                      trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(key: const ValueKey('reorder-done'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Done')),
            ),
          ]),
        ),
      ),
    );
    if (done == true) await ref.read(sessionRepositoryProvider).reorderExercises([for (final e in order) e.row.id]);
  }

  /// If the workout started from a routine and was changed, offers to carry the changes over.
  Future<bool> _offerRoutineUpdate(ActiveSession session, Map<String, ExerciseInfo> catalog) async {
    final routineId = session.session.routineId;
    if (routineId == null) return true;
    final db = ref.read(databaseProvider);
    final rows = await routineRows(db, routineId);
    if (rows.isEmpty && session.exercises.isEmpty) return true;
    // The routine was deleted since the workout started.
    if (!await routineExists(db, routineId)) return true;
    // Started before schema v8 (no links): nothing reliable to compare.
    if (rows.isNotEmpty && session.exercises.every((e) => e.row.routineExerciseId == null)) return true;
    final diff = diffSessionAgainstRoutine(session: session.exercises, routine: rows, catalog: catalog);
    if (diff.isEmpty || !mounted) return true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update routine?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This workout differs from the routine:'),
            const SizedBox(height: 8),
            for (final l in diff.lines) Text('• $l', style: AppType.bodyS),
          ]),
        ),
        actions: [
          TextButton(key: const ValueKey('keep-routine'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep routine as is')),
          FilledButton(key: const ValueKey('update-routine'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Update routine')),
        ],
      ),
    );
    if (choice == null) return false; // dismissed: stay in the workout
    if (choice) {
      await updateRoutineFromSession(
        db: db,
        routineId: routineId,
        session: session.exercises,
        catalog: catalog,
        program: await ref.read(programProvider.future),
      );
    }
    return true;
  }

  /// Program substitutions first (resolved to library exercises), then a library search.
  Future<void> _replace(ActiveExercise ex, Map<String, ExerciseInfo> catalog) async {
    final program = await ref.read(programProvider.future);
    if (!mounted) return;
    final slots = decodeSlots(ex.row.programSlots);
    final slot = slots.isEmpty ? null : program.slot(slots.first);
    final options = <String>[if (slot != null) slot.exercise, ...?slot?.substitutions];
    final resolver = ExerciseNameResolver(catalog.values);
    final resolved = <(String, ExerciseInfo?)>[for (final o in options) (o, resolver.resolve(o)?.exercise)];
    if (ex.sets.any((s) => s.completed)) {
      final ok = await confirm(context, title: 'Replace exercise?', message: 'Sets already logged on this exercise will be removed.', action: 'Replace', destructive: true);
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
            Text('Replace ${ex.row.displayName ?? catalog[ex.row.exerciseId]?.name ?? ''}', style: AppType.title),
            if (resolved.isNotEmpty) ...[
              const SectionLabel('From the program'),
              for (final (label, info) in resolved)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: info != null && info.id != ex.row.exerciseId,
                  leading: Icon(label == slot?.exercise ? Icons.star_rounded : Icons.swap_horiz_rounded,
                      color: info == null ? AppColors.textTertiary : AppColors.primary),
                  title: Text(label),
                  subtitle: Text(info == null ? 'Not in the library — use search' : (info.id == ex.row.exerciseId ? 'Current exercise' : info.name)),
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
          coach: await ref.read(workoutCoachProvider)(ex.row.sessionId),
          program: program,
        );
  }

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /// Collapses the workout to the mini bar over the tabs; it keeps running.
  Future<void> _minimize() async {
    await _closeKeypad();
    await _saveNotes();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  Future<void> _rename(ActiveSession session) async {
    final name = await promptText(context, title: 'Workout name', initial: session.session.name);
    if (name != null && name.trim().isNotEmpty) await ref.read(sessionRepositoryProvider).renameSession(session.session.id, name.trim());
  }

  Future<void> _addExercise(ActiveSession session) async {
    await _closeKeypad();
    if (!mounted) return;
    final id = await context.push<String>(Routes.pickExercise);
    if (id == null || !mounted) return;
    final catalog = await ref.read(catalogProvider.future);
    final info = catalog[id];
    if (info == null) return;
    final settings = ref.read(currentSettingsProvider);
    final coach = await ref.read(workoutCoachProvider)(session.session.id);
    await ref.read(sessionRepositoryProvider).addExercise(
          sessionId: session.session.id,
          info: info,
          range: info.defaultRange(compound: settings.compoundRange, isolation: settings.isolationRange),
          targetSets: 1, // an added exercise starts with one working set; ADD SET adds more
          restSeconds: info.isCompound ? settings.defaultRestCompound : settings.defaultRestIsolation,
          targetRir: settings.defaultRir,
          coach: coach,
        );
  }

  Future<void> _discard(ActiveSession session) async {
    final ok = await confirm(context, title: 'Discard workout?', message: 'All sets logged in this session will be deleted.', action: 'Discard', destructive: true);
    if (!ok || !mounted) return;
    await ref.read(restTimerProvider).stop();
    await ref.read(sessionRepositoryProvider).discard(session.session.id);
    if (mounted) context.go(Routes.home);
  }

  Future<void> _finish(ActiveSession session, Map<String, ExerciseInfo> catalog) async {
    // Whatever is typed is saved first. A set that was typed into but never ✓'d is a set that was done
    // (you typed its numbers): it's logged as such rather than dropped with the untouched ones.
    final typedSetId = await _commit() ?? _pendingTypedSetId;
    await _closeKeypad(commit: false);
    await _saveNotes();
    final repo = ref.read(sessionRepositoryProvider);
    var current = await repo.loadActive() ?? session;
    if (typedSetId != null) {
      final ex = current.exercises.where((e) => e.sets.any((x) => x.id == typedSetId)).firstOrNull;
      final typed = ex?.sets.where((x) => x.id == typedSetId).firstOrNull;
      if (ex != null && typed != null && !typed.completed) {
        await _complete(current, ex, typed, quiet: true);
        current = await repo.loadActive() ?? current;
      }
    }
    if (!mounted) return;
    final done = current.completedWorkingSets;
    if (done == 0) {
      final discard = await confirm(context,
          title: 'No working sets completed',
          message: 'Complete at least one working set to finish, or discard this workout.',
          action: 'Discard',
          destructive: true);
      if (discard) await _discard(current);
      return;
    }
    final pending = current.exercises.expand((e) => e.sets).where((s) => !s.completed).length;
    if (pending > 0) {
      final ok = await confirm(context,
          title: 'Finish workout?', message: '$pending set${pending == 1 ? '' : 's'} not completed will be dropped.', action: 'Finish');
      if (!ok) return;
    }
    if (!await _offerRoutineUpdate(current, catalog) || !mounted) return;
    setState(() => _finishing = true);
    try {
      await ref.read(restTimerProvider).stop();
      final summary = await ref.read(finishServiceProvider).finish(
            sessionId: current.session.id,
            now: ref.read(clockProvider)(),
            catalog: catalog,
            settings: ref.read(currentSettingsProvider),
            health: ref.read(healthSourceProvider),
          );
      ref.read(lastSummaryProvider.notifier).set(summary);
      if (mounted) context.pushReplacement(summary.rankGains.isEmpty ? Routes.summary : Routes.rankSequence);
    } catch (e, st) {
      ErrorLog.instance.recordCaught(e, st);
      if (mounted) {
        setState(() => _finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not finish: $e')));
      }
    }
  }
}

/// Shown over the tab bar while a workout runs minimized: name, clock or rest, tap to resume.
class MiniWorkoutBar extends ConsumerWidget {
  const MiniWorkoutBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider).value;
    if (session == null) return const SizedBox.shrink();
    return Material(
      color: AppColors.surfaceHigh,
      child: InkWell(
        key: const ValueKey('mini-workout-bar'),
        onTap: () => context.push(Routes.workout),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.outline))),
          child: Row(children: [
            const Icon(Icons.fitness_center_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(session.session.name, overflow: TextOverflow.ellipsis, style: AppType.body.copyWith(fontWeight: FontWeight.w800)),
            ),
            WorkoutClock(startedAt: session.session.startedAt),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.textSecondary),
          ]),
        ),
      ),
    );
  }
}

/// One line, informational only: primary muscles of this routine that are still Fatigued.
class _FatigueHeadsUp extends ConsumerWidget {
  const _FatigueHeadsUp({required this.session, required this.catalog, required this.onDismiss});
  final ActiveSession session;
  final Map<String, ExerciseInfo> catalog;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(recoveryProvider);
    if (r == null) return const SizedBox.shrink();
    final fatigued = fatiguedPrimaries(r, [for (final e in session.exercises) ?catalog[e.row.exerciseId]?.targets]);
    if (fatigued.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('fatigue-heads-up'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.healing_rounded, size: 18, color: AppColors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Heads-up: ${muscleNames(fatigued)} still fatigued',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodyS.copyWith(fontSize: 13),
          ),
        ),
        IconButton(
          tooltip: 'Dismiss',
          visualDensity: VisualDensity.compact,
          onPressed: onDismiss,
          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
        ),
      ]),
    );
  }
}
