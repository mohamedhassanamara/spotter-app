import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/gamification/domain/xp.dart';

// Mondays: 2026-01-05, 01-12, 01-19, 01-26.
DateTime d(int month, int day) => DateTime(2026, month, day, 18);

void main() {

  group('XP', () {
    const xp = XpRules();
    test('per set: 10 XP for every completed working set, whatever the suggestion was', () {
      expect(xp.forSet(const LoggedSet(weight: 80, reps: 8, suggestedWeight: 80)), 10, reason: 'followed it');
      expect(xp.forSet(const LoggedSet(weight: 83, reps: 8, suggestedWeight: 80)), 10);
      expect(xp.forSet(const LoggedSet(weight: 70, reps: 8, suggestedWeight: 80)), 10, reason: 'lighter than suggested');
      expect(xp.forSet(const LoggedSet(weight: 90, reps: 8, suggestedWeight: 80, isOverride: true)), 10, reason: 'heavier than suggested');
      expect(xp.forSet(const LoggedSet(weight: 80, reps: 8)), 10, reason: 'no suggestion');
      expect(xp.forSet(const LoggedSet(weight: 40, reps: 8, isWarmup: true, suggestedWeight: 80)), 0);
      expect(xp.forSet(const LoggedSet(weight: 80, reps: 8, completed: false, suggestedWeight: 80)), 0);
    });

    test('there is no bonus for matching the suggestion', () {
      final matching = [for (var i = 0; i < 4; i++) const LoggedSet(weight: 80, reps: 8, suggestedWeight: 80)];
      final other = [for (var i = 0; i < 4; i++) const LoggedSet(weight: 100, reps: 8, suggestedWeight: 80)];
      expect(xp.forSession(sets: matching, prCount: 0), xp.forSession(sets: other, prCount: 0));
    });

    test('per session with a PR', () {
      final sets = [
        for (var i = 0; i < 3; i++) const LoggedSet(weight: 80, reps: 8, suggestedWeight: 80),
        const LoggedSet(weight: 90, reps: 5, suggestedWeight: 80, isOverride: true),
      ];
      expect(xp.forSession(sets: sets, prCount: 1), 90);
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
