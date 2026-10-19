import '../../../core/live_activity/live_activity_service.dart';
import '../../../core/db/database.dart';
import '../data/session_repository.dart';
import 'rest_preview.dart' show setTarget;
import 'set_kinds.dart';

const _maxWarmupLines = 4;

/// The Live Activity for a running workout: the exercise and set that come next, its warm-ups checked off as they are done,
/// and the rest countdown while one runs. Null when nothing is left to show (every set done). [rest] is the running rest.
WorkoutActivity? buildWorkoutActivity(
  ActiveSession session, {
  required String Function(ActiveExercise) nameOf,
  RestActivity? rest,
}) {
  ({ActiveExercise exercise, WorkoutSet set})? next;
  for (final e in session.exercises) {
    final open = e.sets.where((s) => !s.completed).firstOrNull;
    if (open != null) {
      next = (exercise: e, set: open);
      break;
    }
  }
  final start = session.session.startedAt;
  final name = session.session.name;
  if (rest != null) {
    return WorkoutActivity(
      phase: 'rest',
      workoutName: name,
      exerciseName: rest.exerciseName,
      nextTarget: rest.nextTarget,
      setLabel: next == null ? '' : _label(next.exercise, next.set),
      workoutStart: start,
      restStart: rest.startsAt,
      restEnd: rest.endsAt,
      warmups: next == null ? const [] : _warmups(next.exercise).$1,
      warmupsMore: next == null ? 0 : _warmups(next.exercise).$2,
    );
  }
  if (next == null) {
    return WorkoutActivity(
      phase: 'working',
      workoutName: name,
      exerciseName: 'Workout',
      nextTarget: 'Last set done. Finish when ready',
      setLabel: '',
      workoutStart: start,
    );
  }
  final (lines, more) = _warmups(next.exercise);
  return WorkoutActivity(
    phase: next.set.isWarmup ? 'warmup' : 'working',
    workoutName: name,
    exerciseName: nameOf(next.exercise),
    nextTarget: setTarget(next.exercise, next.set),
    setLabel: _label(next.exercise, next.set),
    workoutStart: start,
    warmups: lines,
    warmupsMore: more,
  );
}

/// "Warm-up 2 of 3", "Set 2 of 3"; empty for other kinds of set.
String _label(ActiveExercise e, WorkoutSet s) {
  final group = switch (s.kind) {
    SetKind.warmup => e.sets.where((x) => x.kind == SetKind.warmup).toList(),
    SetKind.working => e.sets.where((x) => x.isWorkingSet).toList(),
    _ => const <WorkoutSet>[],
  };
  final i = group.indexWhere((x) => x.id == s.id);
  if (i < 0) return '';
  return '${s.kind == SetKind.warmup ? 'Warm-up' : 'Set'} ${i + 1} of ${group.length}';
}

/// The exercise's warm-ups: at most [_maxWarmupLines], starting at the first one not done, plus how many more.
(List<ActivityWarmup>, int) _warmups(ActiveExercise e) {
  final all = e.sets.where((s) => s.kind == SetKind.warmup).toList();
  if (all.isEmpty) return (const [], 0);
  final firstOpen = all.indexWhere((s) => !s.completed);
  // Once they are all done, keep the last few visible (checked) until the working sets start.
  final from = firstOpen < 0 ? (all.length - _maxWarmupLines).clamp(0, all.length) : (firstOpen > 0 ? firstOpen - 1 : 0);
  final shown = all.skip(from).take(_maxWarmupLines).toList();
  final more = all.length - from - shown.length;
  return ([for (final s in shown) ActivityWarmup(_warmupText(e, s), s.completed)], more);
}

String _warmupText(ActiveExercise e, WorkoutSet s) => setTarget(e, s).replaceFirst('Warm-up · ', '');
