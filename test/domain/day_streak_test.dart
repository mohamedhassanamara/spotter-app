import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/gamification/domain/streaks.dart';

// 2026-10-12 is a Monday.
DateTime d(int month, int day) => DateTime(2026, month, day, 18);

DayStreak run({
  required List<DateTime> sessions,
  required DateTime now,
  int goal = 3,
  Set<DateTime> red = const {},
  StreakOffset? offset,
}) {
  final weekly = const StreakCalculator().compute(sessionDays: sessions, redDays: red, goal: goal, now: now);
  return const DayStreakCalculator().compute(weekly: weekly, sessionDays: sessions, now: now, offset: offset);
}

void main() {
  test('no history → 0 days', () {
    final s = run(sessions: const [], now: d(10, 14));
    expect(s.days, 0);
    expect(s.longestDays, 0);
  });

  test('starts on the first session day; every day counts, rest days too', () {
    // Goal 3: Mon, Wed, Fri trained; Sunday → 7 days.
    final s = run(sessions: [d(10, 12), d(10, 14), d(10, 16)], now: d(10, 18));
    expect(s.days, 7);
    expect(s.met, isTrue);
  });

  test('keeps counting while the goal is still achievable', () {
    // Thu with one session, goal 3: 1 + 3 days left ≥ 3 → Mon..Thu count.
    final s = run(sessions: [d(10, 12)], now: d(10, 15));
    expect(s.days, 4);
    expect(s.frozen, isFalse);
    expect(s.sessionsNeeded, 2);
    expect(s.daysLeftInWeek, 3);
  });

  test('stops counting (frozen) once the goal is out of reach this week, breaks only when the week ends', () {
    // Goal 5, one session Monday. Wed: 1 + 4 ≥ 5 counts; Thu: 1 + 3 < 5 → frozen at 3.
    final s = run(sessions: [d(10, 12)], now: d(10, 15), goal: 5);
    expect(s.days, 3);
    expect(s.frozen, isTrue);
    expect(s.sessionsNeeded, 4);
    // The following week: the failed week broke it; the new streak starts Monday.
    final next = run(sessions: [d(10, 12), d(10, 19)], now: d(10, 21), goal: 5);
    expect(next.days, 3);
    expect(next.longestDays, 3);
  });

  test('smart rest days lower the goal', () {
    // Goal 3, two sessions, one Red day without training → goal 2 → met.
    final red = {DateTime(2026, 10, 13)};
    final s = run(sessions: [d(10, 12), d(10, 14)], now: d(10, 18), red: red);
    expect(s.goal, 2);
    expect(s.met, isTrue);
    expect(s.days, 7);
  });

  group('carried-over streak (offset)', () {
    final offset = StreakOffset(date: DateTime(2026, 10, 12), days: 177);

    test('177 on the import day, +1 each following day', () {
      final s = run(sessions: [d(10, 12), d(10, 14)], now: d(10, 14), goal: 5, offset: offset);
      expect(s.days, 179);
      expect(s.longestDays, 179);
      expect(s.carriedOver, isTrue);
    });

    test('weeks before the import are not evaluated', () {
      // A failed week in September doesn't break the carried-over streak.
      final s = run(sessions: [d(9, 1), d(10, 12)], now: d(10, 12), goal: 5, offset: offset);
      expect(s.days, 177);
    });

    test('a failed week after the import breaks it; longest stays at least 177', () {
      // Week of 12 Oct: one session, goal 5 → fails. Week of 19 Oct: Mon–Wed.
      final s = run(sessions: [d(10, 12), d(10, 19), d(10, 20)], now: d(10, 21), goal: 5, offset: offset);
      expect(s.days, 3);
      expect(s.carriedOver, isFalse);
      expect(s.longestDays, greaterThanOrEqualTo(177));
    });

    test('round-trips as a setting', () {
      final back = StreakOffset.decode(offset.encode())!;
      expect(back.days, 177);
      expect(back.date, DateTime(2026, 10, 12));
    });
  });
}
