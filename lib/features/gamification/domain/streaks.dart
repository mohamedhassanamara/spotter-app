import 'dart:convert';
import 'dart:math' as math;

import '../../../core/domain/dates.dart';
import '../../../core/domain/history.dart';

/// A streak carried over from another app (Liftoff): on [date] the streak was [days] long.
/// Stored as a setting, never as fake sessions; it stands in for every day up to [date].
class StreakOffset {
  const StreakOffset({required this.date, required this.days});
  final DateTime date;
  final int days;

  static const settingKey = 'streak_offset';

  String encode() => jsonEncode({'date': dayKey(date), 'days': days});

  static StreakOffset? decode(String? raw) {
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return StreakOffset(date: parseDayKey(j['date'] as String), days: (j['days'] as num).toInt());
  }
}

/// Where today stands for the streak.
enum StreakSafety {
  /// A workout was finished today (today is earned).
  trainedToday,

  /// Trained yesterday; today may be a rest day.
  safe,

  /// Yesterday was a rest day (one of the two allowed).
  oneRestDay,

  /// Two rest days in a row are behind you: train today or the streak resets tonight.
  lastChance,

  /// No streak running (never started).
  none,

  /// The streak was lost: a 3rd day in a row ended without a workout. Shows 0 until the next workout.
  lost,
}

/// The streak under these rules (no weekly goal, no fixed days):
/// - **Today does not count until it is earned.** [days] is the count up to yesterday until a workout
///   is finished today.
/// - A workout day counts the moment the workout is finished.
/// - A rest day inside the allowance (the 1st or 2nd in a row) counts when it ends, at midnight.
/// - When the 3rd day in a row without a workout ends, the streak is lost: 0, until the next workout.
class DayStreak {
  const DayStreak({
    required this.days,
    required this.longestDays,
    required this.safety,
    required this.carriedOver,
    this.lastWorkoutDay,
    this.lastChanceDay,
    this.runStart,
    this.lostRunDays = 0,
  });

  /// Current streak in days: workout days plus the rest days that have ended inside the allowance.
  final int days;
  final int longestDays;
  final StreakSafety safety;

  /// Part of the current streak comes from a [StreakOffset].
  final bool carriedOver;
  final DateTime? lastWorkoutDay;

  /// The day you must train (the 3rd day after the last workout); null when no streak runs.
  final DateTime? lastChanceDay;

  /// First day of the current run (before the offset date when carried over).
  final DateTime? runStart;

  /// When [safety] is [StreakSafety.lost]: how long the streak that was lost had been.
  final int lostRunDays;

  bool get lost => safety == StreakSafety.lost;

  /// A workout finished today is already in [days].
  bool get earnedToday => safety == StreakSafety.trainedToday;

  /// Streak length if you train on [lastChanceDay].
  int? get daysOnLastChance => lastChanceDay == null || runStart == null ? null : _dayIndex(lastChanceDay!) - _dayIndex(runStart!) + 1;

  static const lostMessage = 'Streak lost after 3 days without training';

  static const empty = DayStreak(days: 0, longestDays: 0, safety: StreakSafety.none, carriedOver: false);
}

/// Calendar-day number of a local date: DST-proof (a 23- or 25-hour day is still one day).
int _dayIndex(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

DateTime _fromIndex(int i) {
  final u = DateTime.fromMillisecondsSinceEpoch(i * Duration.millisecondsPerDay, isUtc: true);
  return DateTime(u.year, u.month, u.day);
}

/// Liftoff-style day streak with no weekly goal and no fixed training days:
/// - a workout day counts when the workout is finished; a rest day counts when it ends (midnight), as
///   long as it is the 1st or 2nd in a row. Today never counts before it is earned;
/// - when a 3rd day in a row ends without a workout, the streak resets to 0, and the next workout
///   starts it again at 1;
/// - a workout day is the local day a finished session *started* (crossing midnight doesn't move it);
/// - a [StreakOffset] stands in for everything up to its date (the Liftoff carry-over); the streak is
///   computed under these rules from that date onward.
class DayStreakCalculator {
  const DayStreakCalculator();

  static const int maxRestDays = 2;

  /// [workoutStarts]: start times of finished sessions that had at least one completed working set.
  DayStreak compute({required Iterable<DateTime> workoutStarts, required DateTime now, StreakOffset? offset}) {
    final today = _dayIndex(now.toLocal());
    final offsetDay = offset == null ? null : _dayIndex(offset.date);
    final days = <int>{
      for (final s in workoutStarts)
        if (_dayIndex(s.toLocal()) <= today && (offsetDay == null || _dayIndex(s.toLocal()) > offsetDay)) _dayIndex(s.toLocal()),
    };
    if (offsetDay != null && offsetDay <= today) days.add(offsetDay);
    if (days.isEmpty) return DayStreak.empty;

    final sorted = days.toList()..sort();
    var longest = offset?.days ?? 0;
    // The run alive at the end of the walk.
    int? runStart;
    var carried = false;
    int? last;
    for (final d in sorted) {
      if (last != null && d - last > maxRestDays + 1) {
        // The (maxRestDays + 1)-th rest day ended before this workout: the previous run broke.
        longest = math.max(longest, last + maxRestDays - runStart! + 1);
        runStart = null;
        carried = false;
      }
      if (runStart == null) {
        if (offsetDay != null && d == offsetDay) {
          runStart = offsetDay - offset!.days + 1;
          carried = true;
        } else {
          runStart = d;
        }
      }
      last = d;
    }
    final gap = today - last!;
    if (gap > maxRestDays + 1) {
      final lostRun = last + maxRestDays - runStart! + 1;
      longest = math.max(longest, lostRun);
      return DayStreak(
        days: 0,
        longestDays: longest,
        safety: StreakSafety.lost,
        carriedOver: false,
        lastWorkoutDay: _fromIndex(last),
        lostRunDays: lostRun,
      );
    }
    // Through today when a workout is done today, else through yesterday (today is not earned yet).
    final current = today - runStart! + (gap == 0 ? 1 : 0);
    longest = math.max(longest, current);
    return DayStreak(
      days: current,
      longestDays: longest,
      safety: switch (gap) {
        0 => StreakSafety.trainedToday,
        1 => StreakSafety.safe,
        2 => StreakSafety.oneRestDay,
        _ => StreakSafety.lastChance,
      },
      carriedOver: carried,
      lastWorkoutDay: _fromIndex(last),
      lastChanceDay: _fromIndex(last + maxRestDays + 1),
      runStart: _fromIndex(runStart),
    );
  }
}

/// How a calendar day shows against the streak.
enum StreakDayMark {
  /// A workout was finished that day.
  workout,

  /// No workout, but it was the 1st or 2nd rest day in a row inside a running streak (it kept the streak alive).
  rest,
}

/// The calendar's marks: [StreakDayMark.workout] on every workout day, [StreakDayMark.rest] on the rest days that kept the streak alive
/// (between two workouts at most [DayStreakCalculator.maxRestDays] days apart, or the days right after the last workout that have already
/// ended). Days that broke the streak, days before it started and today (not earned yet) have no mark.
/// Stays consistent with [DayStreakCalculator.compute], including the offset (the offset day stands in for a workout).
Map<DateTime, StreakDayMark> streakDayMarks({required Iterable<DateTime> workoutStarts, required DateTime now, StreakOffset? offset}) {
  final today = _dayIndex(now.toLocal());
  final offsetDay = offset == null ? null : _dayIndex(offset.date);
  final workouts = <int>{
    for (final s in workoutStarts)
      if (_dayIndex(s.toLocal()) <= today && (offsetDay == null || _dayIndex(s.toLocal()) > offsetDay)) _dayIndex(s.toLocal()),
  };
  if (offsetDay != null && offsetDay <= today) workouts.add(offsetDay);
  final sorted = workouts.toList()..sort();
  final marks = <int, StreakDayMark>{for (final d in sorted) d: StreakDayMark.workout};
  const maxRest = DayStreakCalculator.maxRestDays;
  for (var i = 0; i < sorted.length; i++) {
    final d = sorted[i];
    final next = i + 1 < sorted.length ? sorted[i + 1] : null;
    final rest = next == null ? maxRest : math.min(maxRest, next - d - 1);
    // A gap longer than the allowance broke the streak at its 3rd day: only the first two days of it kept it alive.
    for (var k = 1; k <= rest; k++) {
      final day = d + k;
      if (day < today) marks[day] = StreakDayMark.rest;
    }
  }
  return {for (final e in marks.entries) _fromIndex(e.key): e.value};
}

/// Start times of finished sessions that count for the streak (at least one completed working set).
List<DateTime> streakWorkoutStarts(TrainingHistory history) => [
      for (final s in history.sessions)
        if (s.exercises.any((e) => e.workingSets.isNotEmpty)) s.startedAt,
    ];

/// Display-only: finished sessions this week (Monday–Sunday) for Profile.
int sessionsThisWeek(TrainingHistory history, DateTime now) {
  final start = weekStart(dateOnly(now));
  return history.sessions.where((s) => !dateOnly(s.startedAt).isBefore(start) && !s.startedAt.isAfter(now)).length;
}

/// The last-chance reminder: 18:00 on the day you must train to keep the streak (two rest days are
/// behind you), "Train today to keep your N-day streak." Null when there's nothing to remind about
/// (no streak, reminder off, or 18:00 that day has passed).
({DateTime at, String body})? streakReminderPlan(DayStreak streak, DateTime now, {required bool enabled}) {
  final day = streak.lastChanceDay;
  if (!enabled || day == null || streak.days == 0) return null;
  final at = DateTime(day.year, day.month, day.day, streakReminderHour);
  if (!at.isAfter(now)) return null;
  return (at: at, body: 'Train today to keep your ${streak.days}-day streak.');
}

const int streakReminderHour = 18;
