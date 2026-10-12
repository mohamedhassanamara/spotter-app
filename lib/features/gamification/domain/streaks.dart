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
