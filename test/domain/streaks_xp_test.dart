import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/gamification/domain/streaks.dart';
import 'package:spotter/features/gamification/domain/xp.dart';

// Mondays: 2026-01-05, 01-12, 01-19, 01-26.
DateTime d(int month, int day) => DateTime(2026, month, day, 18);

void main() {
  const calc = StreakCalculator();

  group('weekly streak', () {
    test('smart rest lowers the goal; a missed week breaks the streak', () {
      final r = calc.compute(
        sessionDays: [
          d(1, 5), d(1, 6), d(1, 7), // week 1: 3 sessions
          d(1, 12), d(1, 14), // week 2: 2 sessions + 1 smart rest
          d(1, 20), // week 3: 1 session
          d(1, 26), d(1, 27), d(1, 28), // week 4 (current): 3 sessions
        ],
        redDays: {DateTime(2026, 1, 13)},
        goal: 3,
        now: d(1, 28),
      );
      expect(r.weeks.map((w) => w.met).toList(), [true, true, false, true]);
      expect(r.weeks[1].effectiveGoal, 2);
      expect(r.current, 1);
      expect(r.longest, 2);
    });

    test('smart rest is capped at 2 per week', () {
      final r = calc.compute(
        sessionDays: [d(1, 5)],
        redDays: {DateTime(2026, 1, 6), DateTime(2026, 1, 7), DateTime(2026, 1, 8)},
        goal: 6,
        now: d(1, 11),
      );
      expect(r.weeks.single.smartRestDays, 2);
      expect(r.weeks.single.effectiveGoal, 4);
    });

    test('a Red day you trained on is not a smart rest day', () {
      final r = calc.compute(sessionDays: [d(1, 5)], redDays: {DateTime(2026, 1, 5)}, goal: 6, now: d(1, 11));
      expect(r.weeks.single.smartRestDays, 0);
    });

    test('future Red days never count', () {
      final r = calc.compute(sessionDays: [d(1, 5)], redDays: {DateTime(2026, 1, 10)}, goal: 6, now: d(1, 7));
      expect(r.weeks.single.smartRestDays, 0);
    });

    test('an unfinished current week does not break the streak', () {
      final r = calc.compute(
        sessionDays: [d(1, 5), d(1, 6), d(1, 12), d(1, 13)],
        redDays: const {},
        goal: 2,
        now: d(1, 20),
      );
      expect(r.current, 2);
      expect(r.thisWeek.sessions, 0);
    });

    test('total smart rest days for achievements', () {
      expect(
        calc.totalSmartRestDays(
          sessionDays: [d(1, 5)],
          redDays: {DateTime(2026, 1, 5), DateTime(2026, 1, 6), DateTime(2026, 1, 7), DateTime(2026, 1, 8), DateTime(2026, 1, 13)},
          now: d(1, 20),
        ),
        3, // week 1: 3 eligible → capped at 2; week 2: 1
      );
    });
  });

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
