import '../../../core/db/database.dart';
import 'set_kinds.dart';

/// Rest around warm-up sets. The Min-Max program (both PDFs, "Rest" in How to Run this Program) says: "Between working sets:
/// follow the listed rest time. **Between warm-up sets: rest 0–60 seconds.** Between exercises: rest 1–2 minutes as needed."
/// It says nothing about the rest between the last warm-up and the first working set, so that one is this app's choice. Round 3 item 6:
/// no timer at all between warm-ups (the lifter goes straight on, as in the program's "0 seconds" end of that range); one rest of 1:30 after the last
/// warm-up, before the first working set.
/// (docs/DECISIONS.md, "Rest after warm-ups")
class WarmupRest {
  const WarmupRest._();

  /// Between the last warm-up and the first working set: not in the program; 1:30 for the heavier first set.
  static const int beforeFirstWorking = 90;

  /// The rest to run after the warm-up [done] of [sets] (the exercise's sets in order): 1:30 when the next set is the first
  /// working set, none between warm-ups, none after the last set or before a follow-up (drop, myo, hold).
  static int? after(List<WorkoutSet> sets, WorkoutSet done) {
    final i = sets.indexWhere((s) => s.id == done.id);
    if (i < 0 || i + 1 >= sets.length) return null;
    final next = sets[i + 1];
    if (next.isFollowUp || next.isWarmup) return null;
    return beforeFirstWorking;
  }
}
