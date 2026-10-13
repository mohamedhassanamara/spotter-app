import '../../../core/db/database.dart';
import '../data/session_repository.dart';
import 'set_kinds.dart';

/// A superset round: working set i of every partner, with its follow-ups (warm-ups come first, before
/// round 1). Returns each exercise's sets grouped that way.
List<List<WorkoutSet>> _rounds(ActiveExercise e) {
  final rounds = <List<WorkoutSet>>[];
  for (final s in e.sets) {
    if (s.isWarmup) continue;
    if (s.isFollowUp && rounds.isNotEmpty) {
      rounds.last.add(s);
    } else {
      rounds.add([s]);
    }
  }
  return rounds;
}

/// Set order of the whole workout with supersets alternating: A1 warm-ups, A2 warm-ups, then A1 set 1
/// (+ its drops), A2 set 1, A1 set 2, A2 set 2… Exercises outside a superset keep their own order.
List<WorkoutSet> supersetOrder(List<ActiveExercise> exercises) {
  final out = <WorkoutSet>[];
  final done = <int>{};
  for (final e in exercises) {
    if (done.contains(e.row.id)) continue;
    final group = e.row.supersetGroup;
    final members = group == null ? [e] : exercises.where((x) => x.row.supersetGroup == group).toList();
    done.addAll(members.map((m) => m.row.id));
    if (members.length == 1) {
      out.addAll(e.sets);
      continue;
    }
    for (final m in members) {
      out.addAll(m.sets.where((s) => s.isWarmup));
    }
    final rounds = [for (final m in members) _rounds(m)];
    final n = rounds.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);
    for (var i = 0; i < n; i++) {
      for (final r in rounds) {
        if (i < r.length) out.addAll(r[i]);
      }
    }
  }
  return out;
}

/// After completing [setId] of [exerciseId]: is its superset round finished? True when every partner
/// that has a set in this round has completed it (the set just completed counts as done).
bool supersetRoundDone(List<ActiveExercise> members, int exerciseId, int setId) {
  final me = members.firstWhere((m) => m.row.id == exerciseId);
  final myRounds = _rounds(me);
  final round = myRounds.indexWhere((r) => r.any((s) => s.id == setId));
  if (round < 0) return true;
  // Rest only after the last set of the round (follow-ups included) of the last partner to go.
  for (final m in members) {
    final r = _rounds(m);
    if (round >= r.length) continue;
    for (final s in r[round]) {
      if (s.id == setId) continue;
      if (!s.completed) return false;
    }
  }
  return true;
}
