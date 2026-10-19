import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/workout/domain/rest_rules.dart';

WorkoutSet set(int id, {bool warmup = false, String? type}) => WorkoutSet(
      id: id,
      sessionExerciseId: 1,
      position: id,
      isWarmup: warmup,
      weight: 50,
      reps: 8,
      completed: false,
      isOverride: false,
      partials: false,
      setType: type,
    );

void main() {
  test('between warm-ups 45 s (the program says 0–60), before the first working set 1:30 (the program is silent)', () {
    final sets = [set(1, warmup: true), set(2, warmup: true), set(3, warmup: true), set(4), set(5)];
    expect(WarmupRest.after(sets, sets[0]), 45);
    expect(WarmupRest.after(sets, sets[1]), 45);
    expect(WarmupRest.after(sets, sets[2]), 90, reason: 'last warm-up → first working set');
    expect(WarmupRest.betweenWarmups, inInclusiveRange(0, 60));
  });

  test('one warm-up goes straight to the working set after 1:30; a lone warm-up with nothing after it has no rest', () {
    final sets = [set(1, warmup: true), set(2)];
    expect(WarmupRest.after(sets, sets[0]), 90);
    expect(WarmupRest.after([set(1, warmup: true)], set(1, warmup: true)), isNull);
  });

  test('a warm-up followed by a drop / myo / hold gets none; an unknown set neither', () {
    final sets = [set(1, warmup: true), set(2, type: 'drop')];
    expect(WarmupRest.after(sets, sets[0]), isNull);
    expect(WarmupRest.after(sets, set(99)), isNull);
  });
}
