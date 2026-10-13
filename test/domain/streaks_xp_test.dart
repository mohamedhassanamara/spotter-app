import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/gamification/domain/xp.dart';

// Mondays: 2026-01-05, 01-12, 01-19, 01-26.
DateTime d(int month, int day) => DateTime(2026, month, day, 18);

void main() {

  group('XP', () {
    const xp = XpRules();
    test('per set', () {
      expect(xp.forSet(const LoggedSet(weight: 80, reps: 8, suggestedWeight: 80)), 25);
      expect(xp.forSet(const LoggedSet(weight: 83, reps: 8, suggestedWeight: 80)), 25);
      expect(xp.forSet(const LoggedSet(weight: 70, reps: 8, suggestedWeight: 80)), 10);
      expect(xp.forSet(const LoggedSet(weight: 80, reps: 8)), 10);
      expect(xp.forSet(const LoggedSet(weight: 90, reps: 8, suggestedWeight: 80, isOverride: true)), 0);
      expect(xp.forSet(const LoggedSet(weight: 40, reps: 8, isWarmup: true, suggestedWeight: 80)), 0);
      expect(xp.forSet(const LoggedSet(weight: 80, reps: 8, completed: false, suggestedWeight: 80)), 0);
    });

    test('per session with a PR', () {
      final sets = [
        for (var i = 0; i < 3; i++) const LoggedSet(weight: 80, reps: 8, suggestedWeight: 80),
        const LoggedSet(weight: 90, reps: 5, suggestedWeight: 80, isOverride: true),
      ];
      expect(xp.forSession(sets: sets, prCount: 1), 125);
    });

    test('level curve 100 × level^1.5', () {
      expect(xpToAdvance(1), 100);
      expect(xpToAdvance(2), 283);
      expect(xpToAdvance(3), 520);
      expect(levelFor(0).level, 1);
      expect(levelFor(99).level, 1);
      expect(levelFor(100).level, 2);
      expect(levelFor(383).level, 3);
      final l = levelFor(500);
      expect(l.level, 3);
      expect(l.xpIntoLevel, 117);
      expect(l.xpForNext, 520);
    });

    test('PRs need a previous best', () {
      expect(isPr(previousBest: 0, sessionBest: 100), isFalse);
      expect(isPr(previousBest: 100, sessionBest: 100.04), isFalse);
      expect(isPr(previousBest: 100, sessionBest: 101), isTrue);
    });
  });
}
