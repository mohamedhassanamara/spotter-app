import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';
import 'package:spotter/features/readiness/domain/readiness.dart';

final now = DateTime(2026, 5, 4, 18);

ExerciseSessionLog log(List<(double, int, double?)> sets, {int day = 1, SuggestionKind kind = SuggestionKind.none}) =>
    ExerciseSessionLog(
      sessionId: day,
      date: DateTime(2026, 5, day),
      suggestionKind: kind,
      sets: [for (final s in sets) LoggedSet(weight: s.$1, reps: s.$2, rpe: s.$3)],
    );

Suggestion run(
  List<ExerciseSessionLog> history, {
  RepRange range = RepRange.compound,
  EquipmentKind eq = EquipmentKind.barbell,
  double? increment,
  int score = 60,
  bool calibrating = false,
  List<String> loadGroups = const [],
  FreezeState? freeze,
}) =>
    const SuggestionEngine().suggest(SuggestionInput(
      range: range,
      targetSets: 3,
      targetRir: 2,
      increment: increment ?? Increments.defaults.of(eq),
      equipment: eq,
      history: history,
      readiness: ExerciseReadiness(score: score, calibrating: calibrating, loadPenaltyGroups: loadGroups),
      now: now,
      freeze: freeze,
    ));

void main() {
  group('e1RM', () {
    test('Epley on effective reps', () {
      expect(estimateOneRm(100, 5, 8), closeTo(123.333, 1e-3)); // 100 × (1 + 7/30)
      expect(estimateOneRm(100, 5, 10), closeTo(116.667, 1e-3));
      expect(estimateOneRm(100, 5, null), closeTo(120, 1e-9), reason: 'missing RPE assumed 9');
    });
  });

  group('double progression', () {
    test('all sets at top of range, RPE ≤ 8 → +1 increment, reps reset to bottom', () {
      final s = run([log([(80, 10, 8), (80, 10, 8), (80, 10, 7.5)])]);
      expect(s.kind, SuggestionKind.increase);
      expect(s.weight, 82.5);
      expect(s.reps, 6);
      expect(s.sets, 3);
      expect(s.headline, 'Today: 82.5 kg × 6, 3 sets, stop at 2 reps in reserve');
      expect(s.why.first, 'Last session (1/5): 80 kg × 10, 10, 10 @ RPE 8, 8, 7.5.');
    });

    test('within the range → same weight, +1 rep on the weakest set', () {
      final s = run([log([(80, 8, 8), (80, 8, 8), (80, 7, 8)])]);
      expect(s.kind, SuggestionKind.addReps);
      expect(s.weight, 80);
      expect(s.reps, 8);
    });

    test('top of range at RPE > 8 → hold weight', () {
      final s = run([log([(80, 10, 9), (80, 10, 9), (80, 10, 9)])]);
      expect(s.kind, SuggestionKind.addReps);
      expect(s.weight, 80);
      expect(s.reps, 10);
    });

    test('missing RPE is treated as 9, so no increase', () {
      final s = run([log([(80, 10, null), (80, 10, null), (80, 10, null)])]);
      expect(s.kind, SuggestionKind.addReps);
      expect(s.weight, 80);
    });

    test('a set below the bottom of the range → −5% rounded down', () {
      final s = run([log([(80, 7, 9), (80, 6, 9.5), (80, 5, 10)])]);
      expect(s.kind, SuggestionKind.reduce);
      expect(s.weight, 75); // 76 → floor to 2.5
      expect(s.reps, 6);
    });

    test('any set at RPE 10 → −5%', () {
      final s = run([log([(80, 8, 8), (80, 8, 9), (80, 8, 10)])]);
      expect(s.kind, SuggestionKind.reduce);
      expect(s.weight, 75);
    });

    test('plateau: two consecutive sessions without progress → −10% for one session', () {
      final s = run([
        log([(80, 8, 8.5), (80, 8, 8.5), (80, 7, 8.5)], day: 1),
        log([(80, 8, 8.5), (80, 8, 8.5), (80, 7, 8.5)], day: 2),
        log([(80, 8, 9), (80, 7, 9), (80, 7, 9)], day: 3),
      ]);
      expect(s.kind, SuggestionKind.plateauDeload);
      expect(s.weight, 70); // 72 → floor to 2.5
      expect(s.reps, 7);
    });

    test('lower RPE counts as progress (no plateau)', () {
      final s = run([
        log([(80, 8, 9), (80, 8, 9), (80, 7, 9)], day: 1),
        log([(80, 8, 8.5), (80, 8, 8.5), (80, 7, 8.5)], day: 2),
        log([(80, 8, 8.5), (80, 8, 8.5), (80, 7, 8.5)], day: 3),
      ]);
      expect(s.kind, SuggestionKind.addReps);
    });

    test('after a plateau deload the lifter rebuilds (no repeat deload)', () {
      final s = run([
        log([(80, 8, 8.5), (80, 8, 8.5), (80, 7, 8.5)], day: 1),
        log([(80, 8, 8.5), (80, 8, 8.5), (80, 7, 8.5)], day: 2),
        log([(72.5, 9, 8.5), (72.5, 9, 8.5), (72.5, 8, 8.5)], day: 3, kind: SuggestionKind.plateauDeload),
      ]);
      expect(s.kind, SuggestionKind.addReps);
      expect(s.weight, 72.5);
      expect(s.reps, 9);
    });

    test('warm-up sets are ignored', () {
      final s = run([
        ExerciseSessionLog(sessionId: 1, date: DateTime(2026, 5, 1), sets: const [
          LoggedSet(weight: 40, reps: 3, rpe: 5, isWarmup: true),
          LoggedSet(weight: 80, reps: 10, rpe: 8),
          LoggedSet(weight: 80, reps: 10, rpe: 8),
        ]),
      ]);
      expect(s.kind, SuggestionKind.increase);
      expect(s.weight, 82.5);
    });
  });

  group('rounding', () {
    test('dumbbell increments of 2 kg', () {
      final up = run([log([(22, 15, 8), (22, 15, 8), (22, 15, 8)])], range: RepRange.isolation, eq: EquipmentKind.dumbbell);
      expect(up.weight, 24);
      final down = run([log([(22, 9, 9), (22, 9, 9), (22, 8, 9)])], range: RepRange.isolation, eq: EquipmentKind.dumbbell);
      expect(down.weight, 20); // 20.9 → 20
    });

    test('light weights still drop by at least one increment', () {
      final s = run([log([(10, 4, 10)])]);
      expect(s.weight, 7.5); // 9.5 → floor 7.5
    });

    test('increase is one increment even when that exceeds 5%', () {
      final s = run([log([(10, 15, 7), (10, 15, 7)])], range: RepRange.isolation, eq: EquipmentKind.dumbbell);
      expect(s.weight, 12);
    });

    test('helpers', () {
      expect(floorToIncrement(76, 2.5), 75);
      expect(floorToIncrement(77.5, 2.5), 77.5);
      expect(floorToIncrement(59.9999999, 2.5), 60);
      expect(roundToIncrement(81.3, 2.5), 82.5);
      expect(roundToIncrement(80.2, 2), 80);
    });
  });

  group('readiness modifiers', () {
    final topAtEight = [log([(80, 10, 8), (80, 10, 8), (80, 10, 8)])];

    test('Green: as computed', () {
      expect(run(topAtEight, score: 70).weight, 82.5);
    });

    test('Yellow: an increase becomes a hold, sets unchanged', () {
      final s = run(topAtEight, score: 45);
      expect(s.band, ReadinessBand.yellow);
      expect(s.weight, 80);
      expect(s.reps, 10);
      expect(s.sets, 3);
      expect(s.kind, SuggestionKind.addReps);
    });

    test('Red: −10% and one fewer set, technique day', () {
      final s = run(topAtEight, score: 30);
      expect(s.weight, 72.5); // 82.5 × 0.9 = 74.25 → 72.5
      expect(s.sets, 2);
      expect(s.techniqueDay, isTrue);
      expect(s.headline, 'Technique day: 72.5 kg × 6, 2 sets, stop at 2 reps in reserve');
    });

    test('training-load penalty turns a neutral 60 into Yellow (50)', () {
      final s = run(topAtEight, score: 60, loadGroups: ['Chest']);
      expect(s.band, ReadinessBand.yellow);
      expect(s.weight, 80);
      expect(s.why.any((w) => w.startsWith('Chest volume')), isTrue);
    });
  });

  group('technique days', () {
    test('a Red technique day is not used as the progression base', () {
      final s = run([
        log([(80, 10, 8), (80, 10, 8), (80, 10, 8)], day: 1),
        ExerciseSessionLog(
          sessionId: 2,
          date: DateTime(2026, 5, 3),
          techniqueDay: true,
          sets: const [LoggedSet(weight: 72.5, reps: 6, rpe: 6), LoggedSet(weight: 72.5, reps: 6, rpe: 6)],
        ),
      ]);
      expect(s.kind, SuggestionKind.increase);
      expect(s.weight, 82.5, reason: 'progresses from the 80 kg session, not the 72.5 kg technique day');
    });
  });

  group('new exercise', () {
    test('barbell calibration starts at the empty bar and ramps', () {
      final s = run(const []);
      expect(s.kind, SuggestionKind.calibration);
      expect(s.weight, 20);
      expect(s.rampUp, isTrue);
      expect(s.headline, 'Calibration: start at 20 kg and ramp up, 3 sets, stop each set at RPE 8');
    });

    test('dumbbell calibration starts at the lightest dumbbell', () {
      expect(run(const [], eq: EquipmentKind.dumbbell).weight, 2);
    });

    test('the best calibration set seeds the next session', () {
      // Best e1RM: 60 × (1 + (6 + 2)/30) = 76 → weight for 6 reps at 2 RIR = 76 / 1.2667 = 60.
      final s = run([
        log([(20, 8, 6), (40, 8, 7), (60, 6, 8)], kind: SuggestionKind.calibration),
      ]);
      expect(s.kind, SuggestionKind.seeded);
      expect(s.weight, 60);
      expect(s.reps, 6);
    });
  });

  group('ego freeze', () {
    test('active freeze: 5% below the base weight, progression frozen', () {
      final s = run(
        [log([(80, 10, 8), (80, 10, 8), (80, 10, 8)])],
        freeze: FreezeState(until: now.add(const Duration(days: 3)), baseWeight: 80),
      );
      expect(s.kind, SuggestionKind.egoFreeze);
      expect(s.weight, 75); // 76 → 75
      expect(s.reps, 6);
    });

    test('expired freeze has no effect', () {
      final s = run(
        [log([(80, 10, 8), (80, 10, 8), (80, 10, 8)])],
        freeze: FreezeState(until: now.subtract(const Duration(minutes: 1)), baseWeight: 80),
      );
      expect(s.kind, SuggestionKind.increase);
    });
  });
}
