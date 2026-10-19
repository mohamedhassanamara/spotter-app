import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/domain/guardrail.dart';
import 'package:spotter/features/coach/domain/praise.dart';

LoggedSet set(double kg, int reps, {double? rpe = 10, double suggested = 80, int min = 6, int max = 8, int? rir = 0, bool override = true}) =>
    LoggedSet(weight: kg, reps: reps, rpe: rpe, suggestedWeight: suggested, isOverride: override, targetMin: min, targetMax: max, targetRir: rir);

ExerciseSessionLog session(int day, List<LoggedSet> sets) =>
    ExerciseSessionLog(sessionId: day, date: DateTime(2026, 10, day), suggestionKind: SuggestionKind.none, sets: sets);

void main() {
  group('good override', () {
    test('heavier than suggested, reps in the range, effort as prescribed → good, disciplined, valid for records, not ego', () {
      final s = set(90, 7);
      expect(s.isOverride, isTrue);
      expect(s.isGoodOverride, isTrue);
      expect(s.isDisciplined, isTrue);
      expect(s.isEgoSet, isFalse);
      expect(s.isValidForRecords, isTrue);
      expect(set(90, 10).isGoodOverride, isTrue, reason: 'above the top of the range is fine too');
    });

    test('below the range stays an ego warning; going past the prescribed effort is not a good override', () {
      final ego = set(90, 5);
      expect(ego.isGoodOverride, isFalse);
      expect(ego.isEgoSet, isTrue);
      expect(ego.isDisciplined, isFalse);
      expect(ego.isValidForRecords, isFalse);
      final tooHard = set(90, 7, rpe: 10, rir: 2); // prescribed 2 in reserve (RPE 8), logged to failure
      expect(tooHard.isGoodOverride, isFalse);
      expect(set(90, 7, rpe: 8, rir: 2).isGoodOverride, isTrue);
      expect(set(90, 7, rpe: null, rir: 2).isGoodOverride, isTrue, reason: 'no effort logged: not held against it');
    });

    test('not an override (within ±5 %) is not "good override"; it is the plain followed case', () {
      final plain = set(82, 7, override: false);
      expect(plain.isGoodOverride, isFalse);
      expect(plain.isDisciplined, isTrue);
      expect(set(70, 7, override: false).isDisciplined, isFalse, reason: 'lighter than suggested');
    });

    test('discipline % counts followed sets and good overrides, not ego sets', () {
      final pct = const Guardrail().disciplinePct([set(80, 7, override: false), set(90, 7), set(90, 5), set(70, 7, override: false)]);
      expect(pct, 50);
    });

    test('a good override never triggers the ego flag, even when the weight went up and the e1RM went down', () {
      // Weight up each session by overrides that stayed in range; e1RM falls because reps fell. Bad overrides would flag it.
      final good = [
        session(1, [set(80, 8, override: false), set(80, 8, override: false)]),
        session(2, [set(85, 6), set(85, 6)]),
        session(3, [set(90, 6, rpe: 8), set(90, 6, rpe: 8)]),
      ];
      expect(const Guardrail().evaluate(good).flagged, isFalse);
      final bad = [
        session(1, [set(80, 8, override: false), set(80, 8, override: false)]),
        session(2, [set(85, 4), set(85, 4)]),
        session(3, [set(90, 4), set(90, 4)]),
      ];
      expect(const Guardrail().evaluate(bad).flagged, isTrue, reason: 'below the range twice: still an ego warning, as before');
      expect(good.last.hasOverrides, isTrue);
      expect(good.last.hasBadOverrides, isFalse);
    });
  });

  group('praise, in moderation', () {
    const policy = PraisePolicy();

    test('only for a good override', () {
      expect(policy.next(set: set(90, 7), exerciseKey: 1, praisedExercises: {}, given: 0), isNotNull);
      expect(policy.next(set: set(90, 5), exerciseKey: 1, praisedExercises: {}, given: 0), isNull, reason: 'ego warning, no praise');
      expect(policy.next(set: set(80, 7, override: false), exerciseKey: 1, praisedExercises: {}, given: 0), isNull);
    });

    test('at most once per exercise and twice per workout', () {
      final good = set(90, 7);
      final first = policy.next(set: good, exerciseKey: 1, praisedExercises: {}, given: 0)!;
      expect(policy.next(set: good, exerciseKey: 1, praisedExercises: {1}, given: 1), isNull, reason: 'same exercise again');
      final second = policy.next(set: good, exerciseKey: 2, praisedExercises: {1}, given: 1)!;
      expect(policy.next(set: good, exerciseKey: 3, praisedExercises: {1, 2}, given: 2), isNull, reason: 'the third in a workout');
      expect(second, isNot(first), reason: 'varied words');
    });

    test('the wording varies from workout to workout and every message is short', () {
      final seen = {for (var seed = 0; seed < 10; seed++) policy.next(set: set(90, 7), exerciseKey: 1, praisedExercises: {}, given: 0, seed: seed)};
      expect(seen.length, greaterThanOrEqualTo(4));
      for (final m in PraisePolicy.messages) {
        expect(m.length, lessThan(60));
      }
      expect(PraisePolicy.messages.length, greaterThanOrEqualTo(4));
      expect(PraisePolicy.perWorkout, 2);
    });
  });
}
