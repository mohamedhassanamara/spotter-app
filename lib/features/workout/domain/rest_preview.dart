import '../../../core/db/database.dart';
import '../../coach/domain/suggestion_engine.dart' show formatKg;
import '../data/session_repository.dart';
import 'set_kinds.dart';

/// The next set after [done] (just completed in [ex]): the exercise that follows the rest and its
/// target, for the Live Activity. In a superset the group's earlier members come first. Null when
/// nothing is left in the workout.
({ActiveExercise exercise, WorkoutSet set})? nextSetAfter(ActiveSession session, ActiveExercise ex, WorkoutSet done) {
  WorkoutSet? firstOpen(ActiveExercise e, {int from = 0}) {
    for (final s in e.sets.skip(from)) {
      if (!s.completed && s.id != done.id) return s;
    }
    return null;
  }

  final here = ex.sets.indexWhere((s) => s.id == done.id);
  final group = ex.row.supersetGroup;
  if (group != null) {
    // A round isn't done until every member has had its set: look at the group from its first member.
    for (final e in session.exercises.where((e) => e.row.supersetGroup == group)) {
      final s = firstOpen(e);
      if (s != null) return (exercise: e, set: s);
    }
  } else {
    final s = firstOpen(ex, from: here + 1);
    if (s != null) return (exercise: ex, set: s);
  }
  final order = session.exercises.indexWhere((e) => e.row.id == ex.row.id);
  for (final e in session.exercises.skip(order + 1)) {
    final s = firstOpen(e);
    if (s != null) return (exercise: e, set: s);
  }
  for (final e in session.exercises.take(order)) {
    final s = firstOpen(e);
    if (s != null) return (exercise: e, set: s);
  }
  return null;
}

/// "Set 3 · 80 kg × 8", "Warm-up · 40 kg × 8", "Drop set · 60 kg × 8".
String setTarget(ActiveExercise e, WorkoutSet s) {
  final kind = s.kind;
  final label = switch (kind) {
    SetKind.working => 'Set ${e.sets.where((x) => x.isWorkingSet).toList().indexWhere((x) => x.id == s.id) + 1}',
    _ => kind.label,
  };
  final load = s.weight == 0 ? '' : (s.weight < 0 ? '${formatKg(-s.weight)} kg assist' : '${formatKg(s.weight)} kg');
  final reps = kind == SetKind.hold ? '${s.reps} s' : '${s.reps} reps';
  final parts = [if (load.isNotEmpty) load, if (s.reps > 0) reps];
  return parts.isEmpty ? label : '$label · ${parts.join(' × ').replaceFirst(' reps', '')}';
}
