import '../../../core/db/database.dart';
import 'set_kinds.dart';

/// Rest around warm-up sets. The Min-Max program (both PDFs, "Rest" in How to Run this Program) says: "Between working sets:
/// follow the listed rest time. **Between warm-up sets: rest 0–60 seconds.** Between exercises: rest 1–2 minutes as needed."
/// It says nothing about the rest between the last warm-up and the first working set, so that one is this app's choice.
/// (docs/DECISIONS.md, "Rest after warm-ups")
class WarmupRest {
  const WarmupRest._();

  /// Between warm-up sets: inside the program's 0–60 s, towards the upper end so the pyramid is not rushed.
  static const int betweenWarmups = 45;

  /// Between the last warm-up and the first working set: not in the program; 1:30 for the heavier first set.
  static const int beforeFirstWorking = 90;

  /// The rest to run after the warm-up [done] of [sets] (the exercise's sets in order), or null when none follows
  /// (the last set, or a follow-up). 45 s before another warm-up, 1:30 before the first working set.
  static int? after(List<WorkoutSet> sets, WorkoutSet done) {
    final i = sets.indexWhere((s) => s.id == done.id);
    if (i < 0 || i + 1 >= sets.length) return null;
    final next = sets[i + 1];
    if (next.isFollowUp) return null;
    return next.isWarmup ? betweenWarmups : beforeFirstWorking;
  }
}
