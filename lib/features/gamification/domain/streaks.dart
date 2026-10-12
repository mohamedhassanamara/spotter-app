import 'dart:convert';
import 'dart:math' as math;

import '../../../core/domain/dates.dart';

class WeekStatus {
  const WeekStatus({
    required this.weekStart,
    required this.sessions,
    required this.smartRestDays,
    required this.goal,
    required this.effectiveGoal,
  });

  final DateTime weekStart;
  final int sessions;
  final int smartRestDays;
  final int goal;
  final int effectiveGoal;

  bool get met => sessions >= effectiveGoal;
}

class StreakResult {
  const StreakResult({required this.current, required this.longest, required this.thisWeek, required this.weeks});
  final int current;
  final int longest;
  final WeekStatus thisWeek;

  /// Oldest first, up to and including the current week.
  final List<WeekStatus> weeks;
}

/// Weekly streak with "smart rest": a Red-readiness day without training lowers that week's
/// goal by 1, at most 2 per week.
class StreakCalculator {
  const StreakCalculator();

  static const int maxSmartRestPerWeek = 2;

  /// [sessionDays]: dates of finished sessions (several per day allowed).
  /// [redDays]: dates whose readiness band was Red.
  StreakResult compute({
    required List<DateTime> sessionDays,
    required Set<DateTime> redDays,
    required int goal,
    required DateTime now,
    Set<int> plannedRestWeekdays = const {},
  }) {
    final today = dateOnly(now);
    final currentWeek = weekStart(today);
    final sessionsPerWeek = <DateTime, int>{};
    final trainedDays = <DateTime>{};
    for (final d in sessionDays) {
      final day = dateOnly(d);
      trainedDays.add(day);
      final w = weekStart(day);
      sessionsPerWeek[w] = (sessionsPerWeek[w] ?? 0) + 1;
    }
    final smartRest = <DateTime, int>{};
    for (final r in redDays) {
      final day = dateOnly(r);
      if (day.isAfter(today) || trainedDays.contains(day)) continue;
      // A Red day that was a planned rest day anyway doesn't lower the goal.
      if (plannedRestWeekdays.contains(day.weekday)) continue;
      final w = weekStart(day);
      smartRest[w] = (smartRest[w] ?? 0) + 1;
    }

    final firstWeek = sessionsPerWeek.keys.fold<DateTime?>(
            null, (min, w) => min == null || w.isBefore(min) ? w : min) ??
        currentWeek;

    final weeks = <WeekStatus>[];
    for (var w = firstWeek; !w.isAfter(currentWeek); w = addDays(w, 7)) {
      final rest = math.min(maxSmartRestPerWeek, smartRest[w] ?? 0);
      weeks.add(WeekStatus(
        weekStart: w,
        sessions: sessionsPerWeek[w] ?? 0,
        smartRestDays: rest,
        goal: goal,
        effectiveGoal: math.max(1, goal - rest),
      ));
    }

    // Longest: any run of met weeks. The current week only counts once it is met.
    var longest = 0, run = 0;
    for (final w in weeks) {
      if (w.met) {
        run++;
        longest = math.max(longest, run);
      } else if (w.weekStart != currentWeek) {
        run = 0;
      }
    }

    // Current: consecutive met weeks ending last week, plus this week if already met.
    var current = 0;
    for (var i = weeks.length - 1; i >= 0; i--) {
      final w = weeks[i];
      if (w.weekStart == currentWeek) {
        if (w.met) current++;
        continue;
      }
      if (!w.met) break;
      current++;
    }

    return StreakResult(current: current, longest: longest, thisWeek: weeks.last, weeks: weeks);
  }

  /// Number of smart rest days (Red, no training), capped per week. Used by achievements.
  int totalSmartRestDays({
    required List<DateTime> sessionDays,
    required Set<DateTime> redDays,
    required DateTime now,
    Set<int> plannedRestWeekdays = const {},
  }) {
    final trained = sessionDays.map(dateOnly).toSet();
    final perWeek = <DateTime, int>{};
    for (final r in redDays) {
      final d = dateOnly(r);
      if (d.isAfter(dateOnly(now)) || trained.contains(d)) continue;
      if (plannedRestWeekdays.contains(d.weekday)) continue;
      perWeek[weekStart(d)] = (perWeek[weekStart(d)] ?? 0) + 1;
    }
    return perWeek.values.fold<int>(0, (s, v) => s + math.min(maxSmartRestPerWeek, v));
  }
}


/// A streak carried over from another app (Liftoff): on [date] the streak was [days] long.
/// Stored as a setting, never as fake sessions; weeks before [date] aren't evaluated.
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

class DayStreak {
  const DayStreak({
    required this.days,
    required this.longestDays,
    required this.frozen,
    required this.sessionsNeeded,
    required this.daysLeftInWeek,
    required this.goal,
    required this.carriedOver,
  });

  /// Current streak in days (rest days included).
  final int days;
  final int longestDays;

  /// This week's goal can no longer be reached: the count has stopped and the streak ends on Sunday
  /// unless more sessions than days remain are logged.
  final bool frozen;

  /// Sessions still needed this week (0 when the goal is met).
  final int sessionsNeeded;

  /// Days after today until the week ends (Sunday).
  final int daysLeftInWeek;

  /// This week's effective goal (smart rest included).
  final int goal;

  /// Part of the current streak comes from a [StreakOffset].
  final bool carriedOver;

  bool get met => sessionsNeeded == 0;
}

/// Liftoff-style day streak on top of the weekly goal:
/// - every day counts (rest days too) while that week's goal is still achievable (at most one
///   session per remaining day) or already met;
/// - the streak breaks only when a week ends below its goal (smart rest lowers the goal), and the new
///   one starts on the following Monday;
/// - with no history before it, the first streak starts on the first session day.
class DayStreakCalculator {
  const DayStreakCalculator();

  DayStreak compute({
    required StreakResult weekly,
    required List<DateTime> sessionDays,
    required DateTime now,
    StreakOffset? offset,
  }) {
    final today = dateOnly(now);
    final perDay = <DateTime, int>{};
    for (final d in sessionDays) {
      final day = dateOnly(d);
      perDay[day] = (perDay[day] ?? 0) + 1;
    }
    final firstSession = perDay.keys.fold<DateTime?>(null, (m, d) => m == null || d.isBefore(m) ? d : m);

    final offsetDay = offset == null ? null : dateOnly(offset.date);
    if (offsetDay == null && firstSession == null) {
      final w = weekly.thisWeek;
      return DayStreak(days: 0, longestDays: 0, frozen: false, sessionsNeeded: w.effectiveGoal, daysLeftInWeek: 7 - today.weekday, goal: w.effectiveGoal, carriedOver: false);
    }
    final evalFrom = offsetDay != null ? weekStart(offsetDay) : (firstSession == null ? weekStart(today) : weekStart(firstSession));
    // Days before [runStart] belong to the previous run (or to the offset).
    var runStart = offsetDay ?? firstSession ?? today;
    var run = offset == null ? 0 : offset.days - 1;
    var longest = offset?.days ?? 0;
    var carried = offset != null;
    var frozen = false;
    WeekStatus? current;

    for (final w in weekly.weeks) {
      if (w.weekStart.isBefore(evalFrom)) continue;
      final isCurrent = w.weekStart == weekStart(today);
      if (isCurrent) current = w;
      var done = 0;
      for (var i = 0; i < 7; i++) {
        final d = addDays(w.weekStart, i);
        if (d.isAfter(today)) break;
        done += perDay[d] ?? 0;
        final remaining = 6 - i;
        final counts = done >= w.effectiveGoal || done + remaining >= w.effectiveGoal;
        if (d.isBefore(runStart)) continue;
        if (counts) {
          run++;
        } else if (isCurrent && d == today) {
          frozen = true;
        }
      }
      if (!isCurrent && !w.met) {
        longest = math.max(longest, run);
        run = 0;
        carried = false;
        runStart = addDays(w.weekStart, 7);
      }
    }
    longest = math.max(longest, run);

    final week = current ?? weekly.thisWeek;
    var doneThisWeek = 0;
    for (var d = weekStart(today); !d.isAfter(today); d = addDays(d, 1)) {
      doneThisWeek += perDay[d] ?? 0;
    }
    return DayStreak(
      days: run,
      longestDays: longest,
      frozen: frozen,
      sessionsNeeded: math.max(0, week.effectiveGoal - doneThisWeek),
      daysLeftInWeek: 7 - today.weekday,
      goal: week.effectiveGoal,
      carriedOver: carried && run > 0,
    );
  }
}
