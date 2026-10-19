import 'dart:math' as math;

import '../../../core/domain/dates.dart';
import '../../../core/domain/history.dart';
import '../../../core/domain/muscles.dart';
import '../../coach/domain/guardrail.dart';
import '../../ranks/domain/ranks.dart';
import 'achievements.dart';
import 'quests.dart';
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

/// Discipline is information only (Profile): it never earns or blocks a reward.
double? disciplineLast30(TrainingHistory history, DateTime now) =>
    const Guardrail().disciplinePct(history.setsSince(addDays(dateOnly(now), -30)));

/// Lifetime stats the achievements are checked against. Nothing in here depends on following suggestions.
/// [sleepMinutesByDay] maps a yyyy-MM-dd day to minutes slept that night; [routineIds] are the current routines.
AchievementStats buildAchievementStats({
  required TrainingHistory history,
  required int longestStreakDays,
  required int totalXp,
  required int prCount,
  RankSummary? ranks,
  Map<String, double> sleepMinutesByDay = const {},
  Set<int> routineIds = const {},
}) {
  int dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  final distinct = <String>{
    for (final s in history.sessions)
      for (final e in s.exercises)
        if (e.workingSets.isNotEmpty) e.exerciseId,
  };
  final bestLift = ranks == null ? -1 : ranks.exercises.fold<int>(-1, (m, r) => r.score.tier.index > m ? r.score.tier.index : m);
  return AchievementStats(
    sessions: history.sessions.length,
    longestStreakDays: longestStreakDays,
    prs: prCount,
    totalVolumeKg: history.sessions.fold<double>(0, (v, s) => v + s.volume),
    totalSets: history.sessions.fold<int>(0, (n, s) => n + s.workingSets.length),
    maxSessionVolumeKg: history.sessions.fold<double>(0, (m, s) => math.max(m, s.volume)),
    level: levelFor(totalXp).level,
    bestExerciseTierIndex: bestLift,
    overallTierIndex: ranks?.overall?.tier.index ?? -1,
    muscleTierIndexes: [for (final m in ranks?.muscles.values ?? const <MuscleRank>[]) m.score.tier.index],
    regionTierIndexes: [for (final r in ranks?.regions.values ?? const <RegionRank>[]) if (r.score != null) r.score!.tier.index],
    distinctExercises: distinct.length,
    greenSessions: history.sessions.where((s) => s.readinessBand == 'green' && s.workingSets.isNotEmpty).length,
    longestSleepStreak: longestSleepStreak({for (final e in sleepMinutesByDay.entries) dayNumber(parseDayKey(e.key)): e.value}),
    fullProgramWeeks: fullProgramWeeks(
      [for (final s in history.sessions) (dayNumber(weekStart(dateOnly(s.startedAt))) ~/ 7, s.routineId)],
      routineIds,
    ),
  );
}

/// Sessions of one week in the shape the challenges understand. [prs] are the PRs of the whole history.
QuestWeek weekActivity(TrainingHistory history, DateTime anyDayInWeek, {List<PrRecord> prs = const [], int sleepNights = 0}) {
  final seen = <String>{};
  final firstSeen = <(int, String)>{};
  for (final s in history.sessions) {
    for (final e in s.exercises) {
      if (e.workingSets.isNotEmpty && seen.add(e.exerciseId)) firstSeen.add((s.id, e.exerciseId));
    }
  }
  return QuestWeek(
    sleepNights: sleepNights,
    sessions: [
      for (final s in history.inWeek(anyDayInWeek))
        SessionActivity(
          date: s.startedAt,
          durationMinutes: s.endedAt?.difference(s.startedAt).inMinutes,
          readinessBand: s.readinessBand,
          prCount: prs.where((p) => p.sessionId == s.id).length,
          exercises: [
            for (final e in s.exercises)
              ExerciseActivity(
                exerciseId: e.exerciseId,
                primaryRegions: e.targets.primaryRegions,
                repMax: e.range.max,
                sets: e.loggedSets,
                isNew: firstSeen.contains((s.id, e.exerciseId)),
              ),
          ],
        ),
    ],
  );
}

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
