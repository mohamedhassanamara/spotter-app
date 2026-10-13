import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/history.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/gamification/domain/streaks.dart';

void main() {
  const calc = DayStreakCalculator();
  DateTime at(int month, int day, [int hour = 18]) => DateTime(2026, month, day, hour);
  DayStreak run(List<DateTime> workouts, DateTime now, {StreakOffset? offset}) => calc.compute(workoutStarts: workouts, now: now, offset: offset);

  test('no workouts → no streak', () {
    final s = run(const [], at(10, 13));
    expect(s.days, 0);
    expect(s.safety, StreakSafety.none);
  });

  test('starts at 1 on the first workout; every calendar day counts, rest days included', () {
    expect(run([at(10, 1)], at(10, 1)).days, 1);
    final s = run([at(10, 1), at(10, 3), at(10, 5)], at(10, 6, 9));
    expect(s.days, 6);
    expect(s.safety, StreakSafety.safe);
  });

  test('2 rest days in a row → the streak continues', () {
    // Workout on the 1st; the 2nd and 3rd are rest days; the 4th is in progress.
    final s = run([at(10, 1)], at(10, 4, 9));
    expect(s.days, 4);
    expect(s.safety, StreakSafety.lastChance);
    expect(s.lastChanceDay, DateTime(2026, 10, 4));
    expect(run([at(10, 1)], at(10, 3, 9)).safety, StreakSafety.oneRestDay);
    expect(run([at(10, 1)], at(10, 2, 9)).safety, StreakSafety.safe);
    // Training on the last chance day keeps it going.
    final saved = run([at(10, 1), at(10, 4)], at(10, 4, 20));
    expect(saved.days, 4);
    expect(saved.safety, StreakSafety.trainedToday);
  });

  test('the 3rd rest day ends → reset to 0', () {
    // Rest on the 2nd, 3rd and 4th; at 00:01 on the 5th the 4th has ended.
    final s = run([at(10, 1)], DateTime(2026, 10, 5, 0, 1));
    expect(s.days, 0);
    expect(s.safety, StreakSafety.none);
    expect(s.longestDays, 3, reason: 'the 1st plus the two allowed rest days');
  });

  test('a workout after the reset starts again at 1', () {
    final s = run([at(10, 1), at(10, 6)], at(10, 6, 20));
    expect(s.days, 1);
    expect(s.safety, StreakSafety.trainedToday);
    expect(run([at(10, 1), at(10, 6)], at(10, 8, 9)).days, 3);
  });

  test('a session crossing midnight counts for the day it started', () {
    final lateNight = DateTime(2026, 10, 1, 23, 40); // finished at 00:50 on the 2nd
    final s = run([lateNight], DateTime(2026, 10, 4, 12));
    expect(s.lastWorkoutDay, DateTime(2026, 10, 1));
    expect(s.safety, StreakSafety.lastChance, reason: 'the 2nd and 3rd were rest days');
  });

  test('an empty workout (no completed working sets) does not count', () {
    HistSession session(DateTime at, List<LoggedSet> sets) => HistSession(
          id: at.day,
          name: 'W',
          routineId: null,
          startedAt: at,
          endedAt: at.add(const Duration(hours: 1)),
          notes: '',
          readinessScore: null,
          readinessBand: null,
          xpEarned: 0,
          exercises: [
            HistExercise(
              id: at.day,
              exerciseId: 'x',
              name: 'X',
              targets: MuscleTargets.empty,
              equipment: EquipmentKind.other,
              range: const RepRange(8, 12),
              targetSets: 2,
              suggestionKind: SuggestionKind.none,
              suggestedWeight: null,
              suggestedReps: null,
              notes: '',
              sets: [for (final (i, s) in sets.indexed) HistSet(id: i, set: s, completedAt: at)],
            ),
          ],
        );
    final history = TrainingHistory([
      session(at(10, 1), const [LoggedSet(weight: 50, reps: 10, rpe: 9)]),
      // Started on the 4th but nothing completed (warm-up only / abandoned).
      session(at(10, 4), const [LoggedSet(weight: 20, reps: 10, isWarmup: true), LoggedSet(weight: 50, reps: 10, completed: false)]),
    ]);
    expect(streakWorkoutStarts(history), [at(10, 1)]);
    final s = run(streakWorkoutStarts(history), DateTime(2026, 10, 5, 0, 1));
    expect(s.days, 0, reason: 'the empty session on the 4th did not save it');
  });

  test('DST: the October clock change (25-hour day) and the March one (23-hour day) are still one day each', () {
    // Europe: clocks go back on 25 Oct 2026, forward on 29 Mar 2026. Local DateTimes either way.
    final oct = run([DateTime(2026, 10, 24, 18)], DateTime(2026, 10, 27, 23, 59));
    expect(oct.safety, StreakSafety.lastChance);
    expect(oct.days, 4);
    expect(run([DateTime(2026, 10, 24, 18)], DateTime(2026, 10, 28, 0, 0, 1)).days, 0);
    final mar = run([DateTime(2026, 3, 28, 18)], DateTime(2026, 3, 31, 1));
    expect(mar.safety, StreakSafety.lastChance);
    expect(mar.days, 4);
  });

  test('time zones: a UTC timestamp counts for its local day', () {
    final local = DateTime(2026, 10, 1, 23, 30);
    final utc = local.toUtc();
    final s = run([utc], DateTime(2026, 10, 1, 23, 45));
    expect(s.lastWorkoutDay, DateTime(2026, 10, 1));
    expect(s.days, 1);
  });

  test('a session later than now is ignored', () {
    expect(run([at(10, 9)], at(10, 8)).days, 0);
  });

  group('carry-over (Liftoff 177 days)', () {
    final offset = StreakOffset(date: DateTime(2026, 10, 11), days: 177);

    test('177 on the import day, +1 every day while alive', () {
      expect(run(const [], DateTime(2026, 10, 11, 20), offset: offset).days, 177);
      final s = run([at(10, 12)], at(10, 13), offset: offset);
      expect(s.days, 179);
      expect(s.carriedOver, isTrue);
      expect(s.longestDays, 179);
    });

    test('recomputed under the new rule from the import date: 3 rest days after it reset it, longest stays ≥ 177', () {
      final s = run([at(10, 16)], at(10, 16, 20), offset: offset);
      expect(s.days, 1, reason: 'the 12th–14th were rest days; it reset when the 14th ended');
      expect(s.carriedOver, isFalse);
      expect(s.longestDays, 179, reason: '177 + the two rest days that were still safe');
    });

    test('sessions before the import date are covered by the offset, not counted again', () {
      final s = run([at(10, 1), at(10, 5)], at(10, 12, 9), offset: offset);
      expect(s.days, 178);
    });

    test('round-trips as a setting', () {
      expect(StreakOffset.decode(offset.encode())!.days, 177);
      expect(StreakOffset.decode(offset.encode())!.date, DateTime(2026, 10, 11));
    });
  });

  test('the reminder day and the streak shown on it', () {
    final s = run([at(10, 1), at(10, 2)], at(10, 3, 9));
    expect(s.lastChanceDay, DateTime(2026, 10, 5));
    expect(s.daysOnLastChance, 5);
  });

  group('last-chance reminder', () {
    test('18:00 on the 3rd day after the last workout, with the streak it would keep', () {
      final s = run([at(10, 1), at(10, 2)], at(10, 3, 9));
      final plan = streakReminderPlan(s, at(10, 3, 9), enabled: true)!;
      expect(plan.at, DateTime(2026, 10, 5, 18));
      expect(plan.body, 'Train today to keep your 5-day streak.');
    });

    test('training moves it; turning it off or passing 18:00 cancels it', () {
      final s = run([at(10, 1), at(10, 5)], at(10, 5, 20));
      expect(streakReminderPlan(s, at(10, 5, 20), enabled: true)!.at, DateTime(2026, 10, 8, 18));
      expect(streakReminderPlan(s, at(10, 5, 20), enabled: false), isNull);
      final late = run([at(10, 1)], DateTime(2026, 10, 4, 19));
      expect(streakReminderPlan(late, DateTime(2026, 10, 4, 19), enabled: true), isNull);
      expect(streakReminderPlan(DayStreak.empty, at(10, 4), enabled: true), isNull);
    });
  });
}
