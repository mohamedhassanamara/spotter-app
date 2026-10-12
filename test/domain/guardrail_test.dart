import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/domain/guardrail.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';

ExerciseSessionLog session(int day, List<LoggedSet> sets) =>
    ExerciseSessionLog(sessionId: day, date: DateTime(2026, 6, day, 18), sets: sets);

// Prescribed range 6–8 unless stated.
const normal = LoggedSet(weight: 80, reps: 8, rpe: 8, suggestedWeight: 80, targetMin: 6, targetMax: 8);
// Too heavy: more than 5 % above the suggestion and below the bottom of the range.
const egoSet = LoggedSet(weight: 90, reps: 5, rpe: 9.5, suggestedWeight: 80, isOverride: true, targetMin: 6, targetMax: 8);
// Ego (7 < 8) but with a better e1RM (90×7 @9.5 → 112.5), so only the repeated-ego trigger can fire.
const strongEgoSet = LoggedSet(weight: 90, reps: 7, rpe: 9.5, suggestedWeight: 80, isOverride: true, targetMin: 8, targetMax: 10);
// Heavier than suggested, to failure, but inside the range: never ego.
const strongOverride = LoggedSet(weight: 90, reps: 6, rpe: 10, suggestedWeight: 80, isOverride: true, targetMin: 6, targetMax: 8);

void main() {
  const g = Guardrail();

  group('override detection', () {
    test('more than 5% above the suggestion', () {
      expect(g.isOverride(weight: 84, suggested: 80, isWarmup: false), isFalse);
      expect(g.isOverride(weight: 84.5, suggested: 80, isWarmup: false), isTrue);
    });

    test('warm-ups and sets without a suggestion never override', () {
      expect(g.isOverride(weight: 120, suggested: 80, isWarmup: true), isFalse);
      expect(g.isOverride(weight: 120, suggested: null, isWarmup: false), isFalse);
    });

    test('bodyweight suggestion: any added load is an override', () {
      expect(g.isOverride(weight: 2.5, suggested: 0, isWarmup: false), isTrue);
      expect(g.isOverride(weight: 0, suggested: 0, isWarmup: false), isFalse);
    });
  });

  group('ego flag', () {
    test('2 of the last 3 sessions with ego sets (too heavy, below the range)', () {
      final r = g.evaluate([
        session(1, [normal, egoSet]),
        session(3, [normal, normal]),
        session(5, [egoSet, normal]),
      ]);
      expect(r.flagged, isTrue);
      expect(r.triggers, {EgoTrigger.repeatedMaxOverrides});
    });

    test('a single ego session is not enough', () {
      final r = g.evaluate([session(1, [normal]), session(3, [normal]), session(5, [strongEgoSet])]);
      expect(r.flagged, isFalse);
    });

    test('heavier than suggested but inside the range (even at failure) is not ego lifting', () {
      final r = g.evaluate([session(1, [strongOverride]), session(3, [strongOverride]), session(5, [normal])]);
      expect(r.flagged, isFalse);
    });

    test('only the last 3 sessions are considered', () {
      final r = g.evaluate([
        session(1, [strongEgoSet]),
        session(2, [normal]),
        session(3, [normal]),
        session(4, [strongEgoSet]),
      ]);
      expect(r.flagged, isFalse);
    });

    test('weight up while e1RM down over the last 3 sessions', () {
      // 80×8 @8 → e1RM 106.67; 85×5 @10 → e1RM 99.17.
      final r = g.evaluate([
        session(1, [const LoggedSet(weight: 80, reps: 8, rpe: 8)]),
        session(3, [const LoggedSet(weight: 82.5, reps: 6, rpe: 9)]),
        session(5, [const LoggedSet(weight: 85, reps: 5, rpe: 10, suggestedWeight: 80, isOverride: true)]),
      ]);
      expect(r.triggers, {EgoTrigger.weightUpE1rmDown});
    });

    test('a coach-prescribed increase that resets reps is not ego lifting', () {
      // 80×10 @8 (e1RM 106.7) → coach adds 2.5 kg and resets reps: 82.5×6 @8 (104.5), 82.5×6 @8.5 (103.1).
      // Weight up and e1RM down, but no overrides: not flagged.
      final r = g.evaluate([
        session(1, [const LoggedSet(weight: 80, reps: 10, rpe: 8, suggestedWeight: 80)]),
        session(3, [const LoggedSet(weight: 82.5, reps: 6, rpe: 8, suggestedWeight: 82.5)]),
        session(5, [const LoggedSet(weight: 82.5, reps: 6, rpe: 8.5, suggestedWeight: 82.5)]),
      ]);
      expect(r.flagged, isFalse);
    });

    test('weight up with e1RM up is real progress', () {
      final r = g.evaluate([
        session(1, [const LoggedSet(weight: 80, reps: 8, rpe: 8)]),
        session(3, [const LoggedSet(weight: 82.5, reps: 8, rpe: 8)]),
        session(5, [const LoggedSet(weight: 85, reps: 8, rpe: 8)]),
      ]);
      expect(r.flagged, isFalse);
    });

    test('sessions before the last freeze started are ignored after expiry', () {
      final history = [session(1, [egoSet]), session(3, [egoSet]), session(12, [normal])];
      expect(g.evaluate(history).flagged, isTrue);
      expect(g.evaluate(history, since: DateTime(2026, 6, 3, 20)).flagged, isFalse);
    });
  });

  group('freeze', () {
    test('lasts 7 days and counts down', () {
      final start = DateTime(2026, 6, 5, 19);
      final f = FreezeState(until: g.freezeUntil(start), baseWeight: 80);
      expect(f.isActive(start.add(const Duration(days: 6))), isTrue);
      expect(f.daysLeft(start.add(const Duration(days: 6))), 1);
      expect(f.daysLeft(start.add(const Duration(days: 2, hours: 1))), 5);
      expect(f.isActive(start.add(const Duration(days: 7))), isFalse);
      expect(f.daysLeft(start.add(const Duration(days: 8))), 0);
    });
  });

  group('rank and PR exclusion', () {
    test('ego sets (override + below the range) are not valid for records', () {
      expect(egoSet.isEgoSet, isTrue);
      expect(egoSet.isValidForRecords, isFalse);
      expect(strongOverride.isValidForRecords, isTrue);
      final l = session(1, [normal, egoSet]);
      // e1RM: normal 80×(1+10/30)=106.67; ego set 90×(1+5.5/30)=106.5 → valid best stays normal.
      expect(l.bestE1rm(validOnly: true), closeTo(106.667, 1e-3));
      final l2 = session(2, [normal, const LoggedSet(weight: 100, reps: 5, rpe: 10, suggestedWeight: 80, isOverride: true, targetMin: 6)]);
      expect(l2.bestE1rm(), closeTo(116.667, 1e-3));
      expect(l2.bestE1rm(validOnly: true), closeTo(106.667, 1e-3));
    });
  });

  group('section 7 rules', () {
    test('failure inside the range is never ego', () {
      expect(strongOverride.isEgoSet, isFalse);
      expect(strongOverride.isValidForRecords, isTrue);
    });

    test('ego = load above the suggestion + reps below the bottom of the range', () {
      expect(egoSet.isEgoSet, isTrue);
      const lightButShort = LoggedSet(weight: 80, reps: 4, suggestedWeight: 80, targetMin: 6);
      expect(lightButShort.isEgoSet, isFalse, reason: 'missing reps at the suggested load is just a hard day');
    });

    test('discipline needs the load within ±5 % and the reps inside the range', () {
      expect(normal.followedSuggestion, isTrue);
      expect(const LoggedSet(weight: 80, reps: 4, suggestedWeight: 80, targetMin: 6, targetMax: 8).followedSuggestion, isFalse);
      expect(const LoggedSet(weight: 80, reps: 12, suggestedWeight: 80, targetMin: 6, targetMax: 8).followedSuggestion, isFalse);
      expect(const LoggedSet(weight: 83, reps: 7, suggestedWeight: 80, targetMin: 6, targetMax: 8).followedSuggestion, isTrue);
    });

    test('drop sets count for volume, not for e1RM, records or progression', () {
      const drop = LoggedSet(weight: 60, reps: 10, rpe: 10, isDrop: true);
      final l = session(1, [normal, drop]);
      expect(l.volume, 80 * 8 + 60 * 10);
      expect(l.workingSets, [normal]);
      expect(drop.isValidForRecords, isFalse);
    });

    test('effort selector: F / 1 / 2 / 3+ ↔ RPE 10 / 9 / 8 / 7, default from the prescribed RIR', () {
      expect(Effort.values.map((e) => e.rpe), [10, 9, 8, 7]);
      expect(Effort.fromRir(0), Effort.failure);
      expect(Effort.fromRir(1), Effort.oneLeft);
      expect(Effort.fromRir(4), Effort.threePlus);
      expect(Effort.fromRpe(9.5), Effort.oneLeft);
      expect(Effort.threePlus.next, Effort.failure);
    });
  });

  group('discipline', () {
    test('% of working sets within ±5% of the suggestion and inside the range', () {
      final pct = g.disciplinePct([
        normal,
        normal,
        const LoggedSet(weight: 83, reps: 8, rpe: 8, suggestedWeight: 80, targetMin: 6, targetMax: 8), // within 5%
        egoSet,
        const LoggedSet(weight: 40, reps: 5, isWarmup: true, suggestedWeight: 80), // ignored
        const LoggedSet(weight: 80, reps: 8), // no suggestion: ignored
      ]);
      expect(pct, 75);
    });

    test('null when nothing to measure', () {
      expect(g.disciplinePct(const []), isNull);
    });
  });
}
