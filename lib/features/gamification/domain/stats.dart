import 'dart:math' as math;

import '../../../core/domain/dates.dart';
import '../../../core/domain/history.dart';
import '../../../core/domain/muscles.dart';
import '../../coach/domain/guardrail.dart';
import 'achievements.dart';
import 'quests.dart';
import 'streaks.dart';
import 'xp.dart';

class PrRecord {
  const PrRecord({required this.sessionId, required this.exerciseId, required this.name, required this.e1rm, required this.previous});
  final int sessionId;
  final String exerciseId;
  final String name;
  final double e1rm;
  final double previous;
}

/// Replays history and returns every valid PR (one per exercise per session at most).
List<PrRecord> findPrs(TrainingHistory history, {Set<String> bodyweightLoaded = const {}, double bodyweight = 0}) {
  final best = <String, double>{};
  final out = <PrRecord>[];
  for (final s in history.sessions) {
    for (final e in s.exercises) {
      final bw = bodyweightLoaded.contains(e.exerciseId) ? bodyweight : 0.0;
      var sessionBest = 0.0;
      for (final set in e.workingSets) {
        if (set.isValidForRecords) sessionBest = math.max(sessionBest, set.e1rm(bodyweight: bw));
      }
      final prev = best[e.exerciseId] ?? 0;
      if (isPr(previousBest: prev, sessionBest: sessionBest)) {
        out.add(PrRecord(sessionId: s.id, exerciseId: e.exerciseId, name: e.name, e1rm: sessionBest, previous: prev));
      }
      if (sessionBest > prev) best[e.exerciseId] = sessionBest;
    }
  }
  return out;
}

double? disciplineLast30(TrainingHistory history, DateTime now) =>
    const Guardrail().disciplinePct(history.setsSince(addDays(dateOnly(now), -30)));

int workingSetsLast30(TrainingHistory history, DateTime now) =>
    history.setsSince(addDays(dateOnly(now), -30)).where((s) => s.suggestedWeight != null).length;

AchievementStats buildAchievementStats({
  required TrainingHistory history,
  required Set<DateTime> redDays,
  required int weeklyGoal,
  required DateTime now,
  required int bestTierIndex,
  required int totalXp,
  required int prCount,
  Set<int> plannedRestWeekdays = const {},
}) {
  const streaks = StreakCalculator();
  final days = [for (final s in history.sessions) s.startedAt];
  return AchievementStats(
    sessions: history.sessions.length,
    longestCleanSessionStreak: longestCleanStreak([for (final s in history.sessions) s.hasOverrides]),
    smartRestDays: streaks.totalSmartRestDays(sessionDays: days, redDays: redDays, now: now, plannedRestWeekdays: plannedRestWeekdays),
    comebacks: countComebacks(history.logsByExercise.values),
    longestWeeklyStreak:
        streaks.compute(sessionDays: days, redDays: redDays, goal: weeklyGoal, now: now, plannedRestWeekdays: plannedRestWeekdays).longest,
    bestExerciseTierIndex: bestTierIndex,
    disciplinePct30: disciplineLast30(history, now),
    workingSets30: workingSetsLast30(history, now),
    prs: prCount,
    totalVolumeKg: history.sessions.fold<double>(0, (v, s) => v + s.volume),
    level: levelFor(totalXp).level,
  );
}

/// Sessions of one week in the shape the quest engine understands.
List<SessionActivity> weekActivity(TrainingHistory history, DateTime anyDayInWeek) => [
      for (final s in history.inWeek(anyDayInWeek))
        SessionActivity(date: s.startedAt, exercises: [
          for (final e in s.exercises)
            ExerciseActivity(exerciseId: e.exerciseId, primaryRegions: e.targets.primaryRegions, repMax: e.range.max, sets: e.loggedSets),
        ]),
    ];

/// % of working sets in the last 30 days that had an RPE logged.
double? rpeLoggedPct(TrainingHistory history, DateTime now) {
  final sets = history.setsSince(addDays(dateOnly(now), -30));
  if (sets.isEmpty) return null;
  return sets.where((s) => s.rpe != null).length / sets.length * 100;
}

/// Working sets per body region over the 4 weeks before [now] (regions of the primary muscles).
Map<BodyRegion, int> regionSetsLast4Weeks(TrainingHistory history, DateTime now) {
  final from = addDays(dateOnly(now), -28);
  final out = <BodyRegion, int>{};
  for (final s in history.inRange(from, now)) {
    for (final e in s.exercises) {
      for (final r in e.targets.primaryRegions) {
        out[r] = (out[r] ?? 0) + e.workingSets.length;
      }
    }
  }
  return out;
}
