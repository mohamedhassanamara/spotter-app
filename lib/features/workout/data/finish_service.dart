import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/history.dart';
import '../../../core/health/health_data_source.dart';
import '../../../core/settings/app_settings.dart';
import '../../coach/data/coach_context.dart';
import '../../coach/domain/guardrail.dart';
import '../../gamification/data/gamification_repository.dart';
import '../../gamification/domain/achievements.dart';
import '../../gamification/domain/quests.dart';
import '../../gamification/domain/stats.dart';
import '../../gamification/domain/streaks.dart';
import '../../gamification/domain/xp.dart';
import '../../library/domain/exercise_info.dart';
import '../../ranks/data/rank_exclusions.dart';
import '../../ranks/data/ranks_repository.dart';
import '../../ranks/domain/ranks.dart';
import '../../readiness/data/readiness_repository.dart';
import 'history_repository.dart';

enum RankChangeScope { exercise, muscle, region, overall }

class RankChange {
  const RankChange({required this.name, required this.fromScore, required this.toScore, required this.scope});
  final String name;
  final RankScore? fromScore;
  final RankScore toScore;
  final RankChangeScope scope;

  String? get from => fromScore?.label;
  String get to => toScore.label;

  /// A first placement counts as up.
  bool get up => fromScore == null || toScore.value > fromScore!.value;

  /// Moved to a better division or tier (not just LP), i.e. worth a rank-up animation.
  bool get isRankUp => fromScore != null && toScore.value > fromScore!.value;
}

class GuardrailFlag {
  const GuardrailFlag({required this.exerciseName, required this.message, required this.freezeUntil});
  final String exerciseName;
  final String message;
  final DateTime? freezeUntil;
}

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.name,
    required this.duration,
    required this.volume,
    required this.workingSets,
    required this.prs,
    required this.xpSession,
    required this.xpBonus,
    required this.levelBefore,
    required this.levelAfter,
    required this.rankChanges,
    required this.overrideSets,
    required this.flags,
    required this.achievements,
    required this.questsCompleted,
    required this.healthSaved,
    this.disciplinePct,
  });

  final int sessionId;
  final String name;
  final Duration duration;
  final double volume;
  final int workingSets;
  final List<PrRecord> prs;
  final int xpSession;
  final int xpBonus;
  final int levelBefore;
  final int levelAfter;
  final List<RankChange> rankChanges;
  final int overrideSets;
  final List<GuardrailFlag> flags;
  final List<AchievementDef> achievements;
  final List<String> questsCompleted;
  final bool? healthSaved;

  /// % of this session's working sets within ±5 % of the suggestion (null without suggestions).
  final double? disciplinePct;

  int get xpTotal => xpSession + xpBonus;

  List<RankChange> get rankUps => rankChanges.where((r) => r.isRankUp).toList();
  List<RankChange> get rankDowns => rankChanges.where((r) => !r.up).toList();
}

/// Everything that happens when a session is finished.
class FinishService {
  FinishService(this._db)
      : _history = HistoryRepository(_db),
        _gami = GamificationRepository(_db),
        _freezes = EgoFreezeRepository(_db),
        _bodyweights = BodyWeightRepository(_db);

  final AppDatabase _db;
  final HistoryRepository _history;
  final GamificationRepository _gami;
  final EgoFreezeRepository _freezes;
  final BodyWeightRepository _bodyweights;

  static const _guardrail = Guardrail();
  static const _xp = XpRules();
  static const _quests = QuestEngine();

  /// Drops sets that were never completed and exercises left without sets.
  Future<void> _prune(int sessionId) async {
    final exRows = await (_db.select(_db.sessionExercises)..where((t) => t.sessionId.equals(sessionId))).get();
    for (final e in exRows) {
      await (_db.delete(_db.workoutSets)..where((t) => t.sessionExerciseId.equals(e.id) & t.completed.equals(false))).go();
      final left = await (_db.select(_db.workoutSets)..where((t) => t.sessionExerciseId.equals(e.id))).get();
      if (left.isEmpty) await (_db.delete(_db.sessionExercises)..where((t) => t.id.equals(e.id))).go();
    }
  }

  Future<RankSummary> _ranks(TrainingHistory history, List<StrengthStandard> standards, Map<String, ExerciseInfo> catalog, DateTime now, Set<String> excluded) async =>
      RanksRepository.compute(
        history: history,
        standards: standards,
        catalog: catalog,
        bodyweights: RanksRepository.timeline(await _bodyweights.all()),
        now: now,
        excluded: excluded,
        myExerciseIds: {for (final r in await _db.select(_db.routineExercises).get()) r.exerciseId},
      );

  /// Unlocks achievements earned by sessions that didn't go through [finish] (the Liftoff import).
  /// Awards no XP.
  Future<List<AchievementDef>> reevaluateAchievements({
    required DateTime now,
    required Map<String, ExerciseInfo> catalog,
    required SettingsModel settings,
  }) async {
    final standards = await RanksRepository.loadStandards();
    final defs = await GamificationRepository.loadAchievementDefs();
    final bwLoaded = RanksRepository.bodyweightLoadedIds(standards, catalog);
    final bodyweight = (await _bodyweights.latest())?.kg ?? 0;
    final excluded = await RankExclusions(_db).load();
    final history = await _history.load(catalog);
    final ranks = await _ranks(history, standards, catalog, now, excluded);
    final stats = buildAchievementStats(
      history: history,
      longestStreakDays: await _longestStreak(history, now),
      now: now,
      bestTierIndex: RanksRepository.bestTierIndex(ranks),
      totalXp: await _gami.totalXp(),
      prCount: findPrs(history, bodyweightLoaded: bwLoaded, bodyweight: bodyweight).length,
    );
    final unlocked = const AchievementEvaluator().newlyUnlocked(defs, stats, await _gami.unlockedKeys());
    if (unlocked.isNotEmpty) await _gami.unlock(unlocked.map((d) => d.key), now);
    return unlocked;
  }

  Future<SessionSummary> finish({
    required int sessionId,
    required DateTime now,
    required Map<String, ExerciseInfo> catalog,
    required SettingsModel settings,
    HealthDataSource? health,
  }) async {
    final standards = await RanksRepository.loadStandards();
    final defs = await GamificationRepository.loadAchievementDefs();
    final bwLoaded = RanksRepository.bodyweightLoadedIds(standards, catalog);
    final bodyweight = (await _bodyweights.latest())?.kg ?? 0;
    final excluded = await RankExclusions(_db).load();

    final before = await _history.load(catalog);
    final xpBefore = await _gami.totalXp();

    await _db.transaction(() async {
      await _prune(sessionId);
      await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
          .write(SessionsCompanion(status: const Value('finished'), endedAt: Value(now)));
    });

    final after = await _history.load(catalog);
    final session = after.sessions.firstWhere((s) => s.id == sessionId);

    // PRs in this session.
    final prs = findPrs(after, bodyweightLoaded: bwLoaded, bodyweight: bodyweight)
        .where((p) => p.sessionId == sessionId)
        .toList();

    // Session XP.
    final xpSession = _xp.forSession(sets: session.workingSets, prCount: prs.length);
    await _gami.addXp(at: now, amount: xpSession, reason: 'session', sessionId: sessionId);
    var bonus = 0;

    // Quests.
    final week = weekStart(session.startedAt);
    final questsDone = <String>[];
    final activity = weekActivity(after, session.startedAt);
    for (final q in await _gami.quests(session.startedAt)) {
      if (q.row.completedAt != null) continue;
      if (_quests.progress(q.def, activity) >= q.def.target) {
        await _gami.completeQuest(q.row.id, now);
        await _gami.addXp(at: now, amount: XpRules.perQuest, reason: 'quest', sessionId: sessionId, week: week);
        bonus += XpRules.perQuest;
        questsDone.add(q.def.title);
      }
    }

    // Ego flags → freezes.
    final flags = <GuardrailFlag>[];
    final freezes = latestFreezes(await _freezes.all());
    for (final e in session.exercises) {
      final existing = freezes[e.exerciseId];
      if (existing != null && existing.until.isAfter(now)) continue;
      final result = _guardrail.evaluate(
        after.logsFor(e.exerciseId),
        since: existing?.startedAt,
        bodyweight: bwLoaded.contains(e.exerciseId) ? bodyweight : 0,
      );
      if (!result.flagged) continue;
      final top = e.workingSets.map((s) => s.weight).fold<double>(double.negativeInfinity, (m, w) => w > m ? w : m);
      final base = e.suggestedWeight ?? top;
      final until = _guardrail.freezeUntil(now);
      await _freezes.add(exerciseId: e.exerciseId, start: now, until: until, baseWeight: base, reason: result.message);
      flags.add(GuardrailFlag(exerciseName: e.name, message: result.message, freezeUntil: until));
    }
    final overrideSets = session.workingSets.where((s) => s.isOverride).length;

    // Rank changes.
    final ranksAfter = await _ranks(after, standards, catalog, now, excluded);
    final rankChanges = _rankChanges(await _ranks(before, standards, catalog, now, excluded), ranksAfter);

    // Achievements.
    final bestTier = RanksRepository.bestTierIndex(ranksAfter);
    final allPrs = findPrs(after, bodyweightLoaded: bwLoaded, bodyweight: bodyweight).length;
    final stats = buildAchievementStats(
      history: after,
      longestStreakDays: await _longestStreak(after, now),
      now: now,
      bestTierIndex: bestTier,
      totalXp: xpBefore + xpSession + bonus,
      prCount: allPrs,
    );
    final unlocked = await _gami.unlockedKeys();
    final newAchievements = const AchievementEvaluator().newlyUnlocked(defs, stats, unlocked);
    if (newAchievements.isNotEmpty) await _gami.unlock(newAchievements.map((d) => d.key), now);

    await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
        .write(SessionsCompanion(xpEarned: Value(xpSession + bonus)));

    // Apple Health.
    bool? saved;
    if (health != null) {
      try {
        saved = await health.writeStrengthWorkout(start: session.startedAt, end: now, title: session.name);
        if (saved) {
          await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
              .write(const SessionsCompanion(healthSynced: Value(true)));
        }
      } catch (e) {
        debugPrint('Health write failed: $e');
        saved = false;
      }
    }

    return SessionSummary(
      sessionId: sessionId,
      name: session.name,
      duration: now.difference(session.startedAt),
      volume: session.volume,
      workingSets: session.workingSets.length,
      prs: prs,
      xpSession: xpSession,
      xpBonus: bonus,
      levelBefore: levelFor(xpBefore).level,
      levelAfter: levelFor(xpBefore + xpSession + bonus).level,
      rankChanges: rankChanges,
      overrideSets: overrideSets,
      flags: flags,
      achievements: newAchievements,
      questsCompleted: questsDone,
      healthSaved: saved,
      disciplinePct: _guardrail.disciplinePct(session.workingSets),
    );
  }

  static List<RankChange> _rankChanges(RankSummary before, RankSummary after) {
    final out = <RankChange>[];
    final beforeEx = {for (final r in before.exercises) r.exerciseId: r.score};
    for (final r in after.exercises) {
      final prev = beforeEx[r.exerciseId];
      if (prev == null || prev.label != r.score.label) {
        out.add(RankChange(name: r.name, fromScore: prev, toScore: r.score, scope: RankChangeScope.exercise));
      }
    }
    for (final m in after.muscles.values) {
      final prev = before.muscles[m.muscle]?.score;
      if (prev == null || prev.label != m.score.label) {
        out.add(RankChange(name: m.muscle.label, fromScore: prev, toScore: m.score, scope: RankChangeScope.muscle));
      }
    }
    for (final r in after.regions.values) {
      final now = r.score;
      if (now == null) continue;
      final prev = before.regions[r.region]?.score;
      if (prev == null || prev.label != now.label) {
        out.add(RankChange(name: r.region.label, fromScore: prev, toScore: now, scope: RankChangeScope.region));
      }
    }
    final o = after.overall, p = before.overall;
    if (o != null && (p == null || p.label != o.label)) {
      out.add(RankChange(name: 'Overall', fromScore: p, toScore: o, scope: RankChangeScope.overall));
    }
    return out;
  }

  /// Longest day streak (the carried-over Liftoff streak included), for streak achievements.
  Future<int> _longestStreak(TrainingHistory history, DateTime now) async => const DayStreakCalculator()
      .compute(workoutStarts: streakWorkoutStarts(history), now: now, offset: StreakOffset.decode(await _db.getSetting(StreakOffset.settingKey)))
      .longestDays;

}
