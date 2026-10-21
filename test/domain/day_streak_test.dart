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
    expect(s.lost, isFalse);
  });

  test('today does not count until it is earned: before training the streak shows the count up to yesterday', () {
    // Trained on the 1st, 2nd and 3rd. On the morning of the 4th: 3, not 4.
    final w = [at(10, 1), at(10, 2), at(10, 3)];
    final morning = run(w, at(10, 4, 7));
    expect(morning.days, 3);
    expect(morning.safety, StreakSafety.safe);
    expect(morning.earnedToday, isFalse);
  });

  test('workout day: the streak increments when the workout is finished', () {
    final w = [at(10, 1), at(10, 2), at(10, 3)];
    expect(run(w, at(10, 4, 7)).days, 3);
    // The 4th session finishes: now 4 (the same day, a second workout adds nothing).
    final done = run([...w, at(10, 4, 8)], at(10, 4, 9));
    expect(done.days, 4);
    expect(done.safety, StreakSafety.trainedToday);
    expect(done.earnedToday, isTrue);
    expect(run([...w, at(10, 4, 8), at(10, 4, 17)], at(10, 4, 19)).days, 4);
  });

  test('starts at 1 on the first workout', () {
    expect(run([at(10, 1)], at(10, 1)).days, 1);
  });

  test('rest day: the 1st and 2nd consecutive rest days count at midnight', () {
    // Workout on the 1st. The 2nd (rest day 1) counts when it ends → 2 on the morning of the 3rd.
    expect(run([at(10, 1)], at(10, 1, 20)).days, 1);
    expect(run([at(10, 1)], at(10, 2, 9)).days, 1, reason: 'the 2nd is in progress: not counted yet');
    expect(run([at(10, 1)], DateTime(2026, 10, 2, 23, 59)).days, 1);
    final midnight = run([at(10, 1)], DateTime(2026, 10, 3, 0, 0, 1));
    expect(midnight.days, 2);
    expect(midnight.safety, StreakSafety.oneRestDay);
    // The 3rd (rest day 2) counts at the next midnight → 3 on the morning of the 4th.
    final second = run([at(10, 1)], DateTime(2026, 10, 4, 0, 0, 1));
    expect(second.days, 3);
    expect(second.safety, StreakSafety.lastChance);
    expect(second.lastChanceDay, DateTime(2026, 10, 4));
  });

  test('training on the 3rd day keeps it going', () {
    // Workout on the 1st; the 4th is the 3rd day without one: it counts once the workout is done.
    final before = run([at(10, 1)], at(10, 4, 9));
    expect(before.days, 3);
    expect(before.safety, StreakSafety.lastChance);
    final saved = run([at(10, 1), at(10, 4)], at(10, 4, 20));
    expect(saved.days, 4);
    expect(saved.safety, StreakSafety.trainedToday);
  });

  test('the 3rd consecutive day without a workout: when it ends the streak resets to 0', () {
    // Rest on the 2nd, 3rd and 4th. Until the 4th ends the streak still stands at 3.
    expect(run([at(10, 1)], DateTime(2026, 10, 4, 23, 59)).days, 3);
    final s = run([at(10, 1)], DateTime(2026, 10, 5, 0, 1));
    expect(s.days, 0);
    expect(s.safety, StreakSafety.lost);
    expect(s.lost, isTrue);
    expect(s.lostRunDays, 3);
    expect(s.longestDays, 3, reason: 'the 1st plus the two allowed rest days');
  });

  test('day 4: opening the app shows 0 and the lost message', () {
    final s = run([at(10, 1)], at(10, 5, 8));
    expect(s.days, 0);
    expect(s.lost, isTrue);
    expect(DayStreak.lostMessage, 'Streak lost after 3 days without training');
  });

  test('opening the app late (2 days after the reset) still shows 0, lost, and the old best', () {
    final s = run([at(10, 1)], at(10, 7, 9));
    expect(s.days, 0);
    expect(s.lost, isTrue);
    expect(s.longestDays, 3);
    expect(s.lastWorkoutDay, DateTime(2026, 10, 1));
    // …and even a month later.
    expect(run([at(10, 1)], at(11, 20)).days, 0);
  });

  test('a workout after the reset starts again at 1; each day after counts at its end', () {
    final s = run([at(10, 1), at(10, 6)], at(10, 6, 20));
    expect(s.days, 1);
    expect(s.safety, StreakSafety.trainedToday);
    expect(s.lost, isFalse);
    expect(run([at(10, 1), at(10, 6)], at(10, 8, 9)).days, 2, reason: 'the 7th ended; the 8th is in progress');
    // Back after 2 days of being away with a workout 2 days after the reset.
    expect(run([at(10, 1), at(10, 7)], at(10, 7, 21)).days, 1);
  });

  test('a mixed week: workout, workout, rest, workout, rest, rest, workout', () {
    final w = [at(10, 1), at(10, 2), at(10, 4), at(10, 7)];
    expect(run(w, at(10, 8, 8)).days, 7);
    expect(run(w, at(10, 7, 22)).days, 7);
    expect(run(w.sublist(0, 3), at(10, 7, 7)).days, 6, reason: 'the 7th is not earned until the workout is finished');
  });

  test('a session crossing midnight counts for the day it started', () {
    final lateNight = DateTime(2026, 10, 1, 23, 40); // finished at 00:50 on the 2nd
    final s = run([lateNight], DateTime(2026, 10, 4, 12));
    expect(s.lastWorkoutDay, DateTime(2026, 10, 1));
    expect(s.safety, StreakSafety.lastChance, reason: 'the 2nd and 3rd were rest days');
    expect(s.days, 3);
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
    expect(s.lost, isTrue);
  });

  test('DST: the October clock change (25-hour day) and the March one (23-hour day) are still one day each', () {
    // Europe: clocks go back on 25 Oct 2026, forward on 29 Mar 2026. Local DateTimes either way.
    final oct = run([DateTime(2026, 10, 24, 18)], DateTime(2026, 10, 27, 23, 59));
    expect(oct.safety, StreakSafety.lastChance);
    expect(oct.days, 3);
    expect(run([DateTime(2026, 10, 24, 18)], DateTime(2026, 10, 28, 0, 0, 1)).days, 0);
    final mar = run([DateTime(2026, 3, 28, 18)], DateTime(2026, 3, 31, 1));
    expect(mar.safety, StreakSafety.lastChance);
    expect(mar.days, 3);
  });

  test('time zones: a UTC timestamp counts for its local day', () {
    final local = DateTime(2026, 10, 1, 23, 30);
    final utc = local.toUtc();
    final s = run([utc], DateTime(2026, 10, 1, 23, 45));
    expect(s.lastWorkoutDay, DateTime(2026, 10, 1));
    expect(s.days, 1);
    expect(run([utc], DateTime(2026, 10, 2, 0, 5)).days, 1);
  });

  test('a session later than now is ignored', () {
    expect(run([at(10, 9)], at(10, 8)).days, 0);
  });

  group('carry-over (Liftoff 177 days)', () {
    final offset = StreakOffset(date: DateTime(2026, 10, 11), days: 177);

    test('177 on the import day; a finished workout adds 1, the next day adds at its end', () {
      expect(run(const [], DateTime(2026, 10, 11, 20), offset: offset).days, 177);
      expect(run(const [], DateTime(2026, 10, 12, 9), offset: offset).days, 177, reason: 'the 12th is not earned yet');
      final s = run([at(10, 12)], at(10, 13), offset: offset);
      expect(s.days, 178, reason: '177 + the 12th; the 13th is in progress');
      expect(s.carriedOver, isTrue);
      expect(s.longestDays, 178);
      expect(run([at(10, 12)], DateTime(2026, 10, 14, 0, 1), offset: offset).days, 179);
    });

    test('recomputed under the new rule from the import date: 3 rest days after it reset it, longest stays ≥ 177', () {
      final s = run([at(10, 16)], at(10, 16, 20), offset: offset);
      expect(s.days, 1, reason: 'the 12th–14th were rest days; it reset when the 14th ended');
      expect(s.carriedOver, isFalse);
      expect(s.longestDays, 179, reason: '177 + the two rest days that were still safe');
      // Opening the app on the 17th and on the 19th (2 days after the reset) with no workout since:
      final late = run(const [], at(10, 16, 9), offset: offset);
      expect(late.days, 0);
      expect(late.lost, isTrue);
      expect(late.lostRunDays, 179);
      expect(late.longestDays, 179);
      expect(run(const [], at(10, 18, 9), offset: offset).lost, isTrue);
    });

    test('sessions before the import date are covered by the offset, not counted again', () {
      final s = run([at(10, 1), at(10, 5)], at(10, 12, 9), offset: offset);
      expect(s.days, 177, reason: 'the 12th is still to be earned');
      expect(run([at(10, 1), at(10, 5)], at(10, 12, 20), offset: offset).days, 177);
    });

    test('round-trips as a setting', () {
      expect(StreakOffset.decode(offset.encode())!.days, 177);
      expect(StreakOffset.decode(offset.encode())!.date, DateTime(2026, 10, 11));
    });
  });

  test('the reminder day and the streak it would keep', () {
    final s = run([at(10, 1), at(10, 2)], at(10, 3, 9));
    expect(s.lastChanceDay, DateTime(2026, 10, 5));
    expect(s.daysOnLastChance, 5);
    expect(s.days, 2);
  });

  group('last-chance reminder', () {
    test('18:00 on the 3rd day after the last workout, with the streak you have', () {
      final s = run([at(10, 1), at(10, 2)], at(10, 3, 9));
      final plan = streakReminderPlan(s, at(10, 3, 9), enabled: true)!;
      expect(plan.at, DateTime(2026, 10, 5, 18));
      expect(plan.body, 'Train today to keep your 2-day streak.');
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

  group('calendar marks', () {
    DateTime day(int d) => DateTime(2026, 10, d);
    Map<DateTime, StreakDayMark> marks(List<DateTime> w, DateTime now, {StreakOffset? offset}) =>
        streakDayMarks(workoutStarts: w, now: now, offset: offset);

    test('workout days get the dumbbell, the rest days between them keep the streak alive (moon)', () {
      final m = marks([at(10, 1), at(10, 2), at(10, 5)], at(10, 6, 9));
      expect(m[day(1)], StreakDayMark.workout);
      expect(m[day(2)], StreakDayMark.workout);
      expect(m[day(3)], StreakDayMark.rest);
      expect(m[day(4)], StreakDayMark.rest);
      expect(m[day(5)], StreakDayMark.workout);
      expect(m[day(6)], isNull, reason: 'today is not earned yet');
    });

    test('a gap that broke the streak stays plain after its two allowed rest days; days before the first workout are plain', () {
      final m = marks([at(10, 1), at(10, 6)], at(10, 7));
      expect(m[day(1)], StreakDayMark.workout);
      expect(m[day(2)], StreakDayMark.rest);
      expect(m[day(3)], StreakDayMark.rest);
      expect(m[day(4)], isNull, reason: 'the 3rd day without a workout ended the streak');
      expect(m[day(5)], isNull);
      expect(m[day(6)], StreakDayMark.workout);
      expect(m[DateTime(2026, 9, 30)], isNull, reason: 'before the streak started');
    });

    test('after the last workout only the rest days that already ended count; today is plain', () {
      final m = marks([at(10, 10)], at(10, 12, 8));
      expect(m[day(11)], StreakDayMark.rest);
      expect(m[day(12)], isNull);
      expect(marks([at(10, 10)], at(10, 13, 8))[day(12)], StreakDayMark.rest);
    });

    test('a workout today shows as a workout day', () {
      expect(marks([at(10, 12, 9)], at(10, 12, 20))[day(12)], StreakDayMark.workout);
    });

    test('the marks agree with the streak: a rest mark never sits on a day the streak counts as broken', () {
      final w = [at(10, 1), at(10, 4)];
      final m = marks(w, at(10, 5));
      expect(calc.compute(workoutStarts: w, now: at(10, 5)).days, 4);
      for (final d in [2, 3]) {
        expect(m[day(d)], StreakDayMark.rest);
      }
    });
  });
}
