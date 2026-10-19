import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/database.dart';
import 'core/diagnostics/error_log.dart';
import 'core/domain/dates.dart';
import 'core/domain/history.dart';
import 'core/domain/muscles.dart';
import 'core/health/fake_health_data_source.dart';
import 'core/health/health_data_source.dart';
import 'core/health/healthkit_data_source.dart';
import 'core/live_activity/live_activity_service.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers.dart';
import 'core/domain/gym.dart';
import 'features/coach/data/gym_repository.dart';
import 'features/coach/domain/energy.dart';
import 'features/coach/domain/suggestion_engine.dart' show FormReset;
import 'features/recovery/domain/recovery.dart';
import 'features/coach/data/coach_context.dart';
import 'features/gamification/data/gamification_repository.dart';
import 'features/gamification/domain/achievements.dart';
import 'features/gamification/domain/quests.dart';
import 'features/gamification/domain/stats.dart';
import 'features/gamification/domain/streaks.dart';
import 'features/gamification/domain/xp.dart';
import 'features/library/data/exercise_repository.dart';
import 'features/library/domain/exercise_info.dart';
import 'features/program/data/program_repository.dart';
import 'features/program/domain/program.dart';
import 'features/ranks/data/ladder_migration.dart';
import 'features/ranks/data/rank_exclusions.dart';
import 'features/ranks/data/ranks_repository.dart';
import 'features/ranks/domain/body_regions.dart';
import 'features/ranks/domain/rank_history.dart';
import 'features/ranks/domain/ranks.dart';
import 'features/readiness/data/readiness_repository.dart';
import 'features/readiness/domain/readiness.dart';
import 'features/workout/data/finish_service.dart';
import 'features/workout/data/history_repository.dart';
import 'features/workout/data/routine_repository.dart';
import 'features/workout/data/session_repository.dart';

export 'core/providers.dart';

// ---------------------------------------------------------------------------
// Services & repositories
// ---------------------------------------------------------------------------

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

/// The rest timer's lock-screen Live Activity (iOS).
final liveActivityProvider = Provider<LiveActivityService>((ref) => defaultLiveActivityService());

final _healthKitProvider = Provider<HealthDataSource>((ref) => HealthKitDataSource());
final _fakeHealthProvider = Provider<HealthDataSource>((ref) => FakeHealthDataSource());

/// Real HealthKit, or the fake source when toggled in the debug menu (debug builds only).
final healthSourceProvider = Provider<HealthDataSource>((ref) {
  final fake = kDebugMode && ref.watch(currentSettingsProvider).useFakeHealth;
  return fake ? ref.watch(_fakeHealthProvider) : ref.watch(_healthKitProvider);
});

final exerciseRepositoryProvider = Provider((ref) => ExerciseRepository(ref.watch(databaseProvider)));
final routineRepositoryProvider = Provider((ref) => RoutineRepository(ref.watch(databaseProvider)));
final sessionRepositoryProvider = Provider((ref) => SessionRepository(ref.watch(databaseProvider)));
final historyRepositoryProvider = Provider((ref) => HistoryRepository(ref.watch(databaseProvider)));
final readinessRepositoryProvider = Provider((ref) => ReadinessRepository(ref.watch(databaseProvider)));
final bodyWeightRepositoryProvider = Provider((ref) => BodyWeightRepository(ref.watch(databaseProvider)));
final freezeRepositoryProvider = Provider((ref) => EgoFreezeRepository(ref.watch(databaseProvider)));
final gamificationRepositoryProvider = Provider((ref) => GamificationRepository(ref.watch(databaseProvider)));
final finishServiceProvider = Provider((ref) => FinishService(ref.watch(databaseProvider)));

// ---------------------------------------------------------------------------
// Catalogue & history
// ---------------------------------------------------------------------------

final catalogProvider = StreamProvider<Map<String, ExerciseInfo>>(
  (ref) => ref.watch(exerciseRepositoryProvider).watchCatalog(),
);

final _historyVersionProvider = StreamProvider<int>((ref) async* {
  var v = 0;
  yield v;
  await for (final _ in ref.watch(historyRepositoryProvider).watchFinishedChanges()) {
    yield ++v;
  }
});

/// All finished sessions. Rebuilt when sessions change or the catalogue loads.
final historyProvider = FutureProvider<TrainingHistory>((ref) async {
  ref.watch(_historyVersionProvider);
  final catalog = await ref.watch(catalogProvider.future);
  return ref.watch(historyRepositoryProvider).load(catalog);
});

final routinesProvider = StreamProvider<List<RoutineWithExercises>>(
  (ref) => ref.watch(routineRepositoryProvider).watchRoutines(),
);

final activeSessionProvider = StreamProvider<ActiveSession?>(
  (ref) => ref.watch(sessionRepositoryProvider).watchActive(),
);

// ---------------------------------------------------------------------------
// Readiness & body
// ---------------------------------------------------------------------------

final dailyMetricsProvider = StreamProvider<List<DailyMetric>>(
  (ref) => ref.watch(readinessRepositoryProvider).watchDays(),
);

final todayReadinessProvider = Provider<ReadinessResult?>((ref) {
  final rows = ref.watch(dailyMetricsProvider).value;
  if (rows == null) return null;
  return ref.watch(readinessRepositoryProvider).computeFor(ref.watch(clockProvider)(), rows);
});

final gymRepositoryProvider = Provider((ref) => GymRepository(ref.watch(databaseProvider)));

/// Settings → My gym equipment (with per-exercise stack overrides).
final gymEquipmentProvider = StreamProvider<GymEquipment>((ref) => ref.watch(gymRepositoryProvider).watch());

/// The loads that exist for one exercise (gym equipment + weights logged on it).
final exerciseGridProvider = Provider.family<WeightGrid?, String>((ref, exerciseId) {
  final info = ref.watch(catalogProvider).value?[exerciseId];
  if (info == null) return null;
  return gridForExercise(ref.watch(gymEquipmentProvider).value ?? GymEquipment.defaults, ref.watch(historyProvider).value ?? TrainingHistory.empty, info);
});

final formResetsProvider = StreamProvider<Map<String, FormReset>>((ref) => ref.watch(gymRepositoryProvider).watchResets());

/// Bodyweight trend (7-day average, 2–4 week slope) and nutrition from Apple Health.
final energyProvider = Provider<EnergyContext>((ref) {
  final weights = ref.watch(_allBodyWeightsProvider).value ?? const [];
  final days = ref.watch(dailyMetricsProvider).value ?? const [];
  return energyFrom(weights, days, ref.watch(clockProvider)());
});

final _allBodyWeightsProvider = StreamProvider<List<BodyWeight>>((ref) => ref.watch(bodyWeightRepositoryProvider).watchAll());

EnergyContext energyFrom(List<BodyWeight> weights, List<DailyMetric> days, DateTime now) => EnergyContext.compute(
      now: now,
      bodyweights: [for (final w in weights) (w.measuredAt, w.kg)],
      nutrition: [for (final d in days) DayNutrition(parseDayKey(d.date), kcal: d.dietaryKcal, proteinG: d.proteinG)],
    );

final latestBodyWeightProvider = StreamProvider<BodyWeight?>(
  (ref) => ref.watch(bodyWeightRepositoryProvider).watchLatest(),
);

final overloadedGroupsProvider = Provider<Set<Muscle>>((ref) {
  final history = ref.watch(historyProvider).value;
  if (history == null) return const {};
  return const TrainingLoad().overloaded(ref.watch(clockProvider)(), groupSetEntries(history));
});

final latestFreezesProvider = StreamProvider<Map<String, EgoFreeze>>(
  (ref) => ref.watch(freezeRepositoryProvider).watchAll().map(latestFreezes),
);

/// Freezes still running now, keyed by exercise id.
final activeFreezesProvider = Provider<Map<String, EgoFreeze>>((ref) {
  final now = ref.watch(clockProvider)();
  final all = ref.watch(latestFreezesProvider).value ?? const {};
  return {for (final e in all.entries) if (e.value.until.isAfter(now)) e.key: e.value};
});

/// Builds a fresh snapshot of everything the suggestion engine needs, as of now.
final coachContextBuilderProvider = Provider<Future<CoachContext> Function()>((ref) {
  return () async {
    final history = await ref.read(historyProvider.future);
    final now = ref.read(clockProvider)();
    final readinessRepo = ref.read(readinessRepositoryProvider);
    final readiness = readinessRepo.computeFor(now, await readinessRepo.allDays());
    final freezes = latestFreezes(await ref.read(freezeRepositoryProvider).all());
    final days = await readinessRepo.allDays();
    final band = readiness.calibrating ? null : readiness.band.name;
    return CoachContext(
      gym: await ref.read(gymRepositoryProvider).load(),
      formResets: await ref.read(gymRepositoryProvider).resets(),
      energy: energyFrom(await ref.read(bodyWeightRepositoryProvider).all(), days, now),
      recovery: computeRecovery(history, now: now, readinessBand: band),
      history: history,
      readiness: readiness,
      overloaded: const TrainingLoad().overloaded(now, groupSetEntries(history)),
      freezes: freezes,
      increments: ref.read(currentSettingsProvider).increments,
      now: now,
      bodyweight: (await ref.read(bodyWeightRepositoryProvider).latest())?.kg ?? 0,
      bodyweightLoaded: await ref.read(bodyweightLoadedIdsProvider.future),
    );
  };
});

/// The coach inputs (readiness, recovery, nutrition, freezes…) a workout was planned with, kept for the
/// whole workout: a Health sync or a readiness refresh while you train never re-plans it.
class FrozenCoachNotifier extends Notifier<({int sessionId, CoachContext coach})?> {
  @override
  ({int sessionId, CoachContext coach})? build() => null;
  void freeze(int sessionId, CoachContext coach) => state = (sessionId: sessionId, coach: coach);
}

final frozenCoachProvider = NotifierProvider<FrozenCoachNotifier, ({int sessionId, CoachContext coach})?>(FrozenCoachNotifier.new);

/// The coach context for anything planned *during* workout [sessionId] (swapping an exercise, a form
/// reset, adding an exercise): the one the workout started with. After a cold restart mid-workout there is
/// none, so it is built once, then frozen.
final workoutCoachProvider = Provider<Future<CoachContext> Function(int sessionId)>((ref) {
  return (sessionId) async {
    final frozen = ref.read(frozenCoachProvider);
    if (frozen != null && frozen.sessionId == sessionId) return frozen.coach;
    final fresh = await ref.read(coachContextBuilderProvider)();
    ref.read(frozenCoachProvider.notifier).freeze(sessionId, fresh);
    return fresh;
  };
});

// ---------------------------------------------------------------------------
// Ranks
// ---------------------------------------------------------------------------

final standardsProvider = FutureProvider<List<StrengthStandard>>((ref) => RanksRepository.loadStandards());

final bodyweightLoadedIdsProvider = FutureProvider<Set<String>>((ref) async {
  final standards = await ref.watch(standardsProvider.future);
  final catalog = await ref.watch(catalogProvider.future);
  return RanksRepository.bodyweightLoadedIds(standards, catalog);
});

/// Exercises hidden from ranking.
final rankExclusionsProvider = StreamProvider<Set<String>>((ref) => RankExclusions(ref.watch(databaseProvider)).watch());

/// Every weigh-in, for scoring each set at the bodyweight of its day.
final bodyweightTimelineProvider = StreamProvider<BodyweightTimeline>(
  (ref) => ref.watch(bodyWeightRepositoryProvider).watchAll().map(RanksRepository.timeline),
);

final ranksProvider = FutureProvider<RankSummary>((ref) async {
  final history = await ref.watch(historyProvider.future);
  final standards = await ref.watch(standardsProvider.future);
  final catalog = await ref.watch(catalogProvider.future);
  final routines = await ref.watch(routinesProvider.future);
  return RanksRepository.compute(
    history: history,
    standards: standards,
    catalog: catalog,
    bodyweights: await ref.watch(bodyweightTimelineProvider.future),
    now: ref.watch(clockProvider)(),
    excluded: await ref.watch(rankExclusionsProvider.future),
    myExerciseIds: {for (final r in routines) for (final e in r.exercises) e.exerciseId},
    displayNames: RanksRepository.displayNamesFor(catalog, [for (final r in routines) for (final e in r.exercises) (exerciseId: e.exerciseId, displayName: e.displayName)]),
  );
});

/// Overall, region and muscle rank over time (weekly), rebuilt from the whole history, Liftoff import included.
final rankEvolutionProvider = FutureProvider<List<RankPoint>>((ref) async {
  final history = await ref.watch(historyProvider.future);
  final routines = await ref.watch(routinesProvider.future);
  final catalog = await ref.watch(catalogProvider.future);
  return rankEvolution(
    history: history,
    standards: await ref.watch(standardsProvider.future),
    catalog: catalog,
    bodyweights: await ref.watch(bodyweightTimelineProvider.future),
    excluded: await ref.watch(rankExclusionsProvider.future),
    now: ref.watch(clockProvider)(),
    displayNames: RanksRepository.displayNamesFor(catalog, [for (final r in routines) for (final e in r.exercises) (exerciseId: e.exerciseId, displayName: e.displayName)]),
  );
});

// ---------------------------------------------------------------------------
// XP, streaks, quests, achievements
// ---------------------------------------------------------------------------

final totalXpProvider = StreamProvider<int>((ref) => ref.watch(gamificationRepositoryProvider).watchTotalXp());

final levelProvider = Provider<LevelInfo>((ref) => levelFor(ref.watch(totalXpProvider).value ?? 0));

/// Streak carried over from Liftoff (setting `streak_offset`), if any.
final streakOffsetProvider = StreamProvider<StreakOffset?>(
  (ref) => ref.watch(databaseProvider).watchSettings().map((m) => StreakOffset.decode(m[StreakOffset.settingKey])),
);

/// Bumps at every local midnight and when the app comes back to the foreground, so anything computed
/// from "today" (the streak counts a rest day at midnight) refreshes without a restart.
class DayTickNotifier extends Notifier<int> {
  Timer? _timer;

  @override
  int build() {
    ref.onDispose(() => _timer?.cancel());
    _arm();
    return 0;
  }

  void _arm() {
    _timer?.cancel();
    final now = ref.read(clockProvider)();
    final next = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(next.difference(now) + const Duration(seconds: 1), () {
      bump();
    });
  }

  void bump() {
    state++;
    _arm();
  }
}

final dayTickProvider = NotifierProvider<DayTickNotifier, int>(DayTickNotifier.new);

/// Liftoff-style day streak: today counts once a workout is finished, a rest day counts at midnight,
/// and it is lost when a 3rd day in a row ends without a workout.
final dayStreakProvider = Provider<DayStreak?>((ref) {
  ref.watch(dayTickProvider);
  final history = ref.watch(historyProvider).value;
  if (history == null) return null;
  return const DayStreakCalculator().compute(
    workoutStarts: streakWorkoutStarts(history),
    now: ref.watch(clockProvider)(),
    offset: ref.watch(streakOffsetProvider).value,
  );
});

/// When to remind about the streak (18:00 on the last-chance day), or null.
final streakReminderProvider = Provider<({DateTime at, String body})?>((ref) {
  final s = ref.watch(dayStreakProvider);
  if (s == null) return null;
  return streakReminderPlan(s, ref.watch(clockProvider)(), enabled: ref.watch(currentSettingsProvider).streakReminder);
});

final disciplineProvider = Provider<double?>((ref) {
  final history = ref.watch(historyProvider).value;
  if (history == null) return null;
  return disciplineLast30(history, ref.watch(clockProvider)());
});

class QuestProgress {
  const QuestProgress(this.quest, this.progress);
  final StoredQuest quest;
  final int progress;
  bool get done => quest.row.completedAt != null || progress >= quest.def.target;
}

/// Generates this week's quests on first access, then streams them with live progress.
final questsProvider = StreamProvider<List<QuestProgress>>((ref) async* {
  final now = ref.watch(clockProvider)();
  final repo = ref.watch(gamificationRepositoryProvider);
  final history = await ref.watch(historyProvider.future);
  await repo.ensureQuests(now, () => const QuestEngine().generate(QuestGenInput(
        sessionsPerWeek: sessionsPerWeekLast4([for (final s in history.sessions) s.startedAt], now),
        groupSets4w: regionSetsLast4Weeks(history, now),
        disciplinePct: disciplineLast30(history, now),
        rpeLoggedPct: rpeLoggedPct(history, now),
      )));
  final activity = weekActivity(history, now);
  yield* repo.watchQuests(now).map((qs) => [
        for (final q in qs) QuestProgress(q, const QuestEngine().progress(q.def, activity)),
      ]);
});

class AchievementState {
  const AchievementState(this.def, this.unlockedAt, this.progress);
  final AchievementDef def;
  final DateTime? unlockedAt;
  final double progress;
}

final achievementStatsProvider = FutureProvider<AchievementStats>((ref) async {
  final history = await ref.watch(historyProvider.future);
  final ranks = await ref.watch(ranksProvider.future);
  final bwIds = await ref.watch(bodyweightLoadedIdsProvider.future);
  final bw = ref.watch(latestBodyWeightProvider).value?.kg ?? 0;
  return buildAchievementStats(
    history: history,
    longestStreakDays: ref.watch(dayStreakProvider)?.longestDays ?? 0,
    now: ref.watch(clockProvider)(),
    bestTierIndex: RanksRepository.bestTierIndex(ranks),
    totalXp: ref.watch(totalXpProvider).value ?? 0,
    prCount: findPrs(history, bodyweightLoaded: bwIds, bodyweight: bw).length,
  );
});

final _unlockedProvider = StreamProvider<Map<String, DateTime>>(
  (ref) => ref.watch(gamificationRepositoryProvider).watchUnlocked(),
);

final achievementsProvider = FutureProvider<List<AchievementState>>((ref) async {
  final defs = await GamificationRepository.loadAchievementDefs();
  final unlocked = ref.watch(_unlockedProvider).value ?? const {};
  final stats = await ref.watch(achievementStatsProvider.future);
  const eval = AchievementEvaluator();
  return [
    for (final d in defs) AchievementState(d, unlocked[d.key], unlocked.containsKey(d.key) ? 1 : eval.progress(d, stats)),
  ];
});

/// Result of the last finished session, shown on the summary screen.
final lastSummaryProvider = NotifierProvider<LastSummaryNotifier, SessionSummary?>(LastSummaryNotifier.new);

class LastSummaryNotifier extends Notifier<SessionSummary?> {
  @override
  SessionSummary? build() => null;

  void set(SessionSummary? s) => state = s;
}

// ---------------------------------------------------------------------------
// Health sync
// ---------------------------------------------------------------------------

class HealthSyncState {
  const HealthSyncState({this.syncing = false, this.lastSync, this.lastResult, this.error});
  final bool syncing;
  final DateTime? lastSync;
  final SyncResult? lastResult;
  final String? error;
}

final healthSyncProvider = NotifierProvider<HealthSyncNotifier, HealthSyncState>(HealthSyncNotifier.new);

class HealthSyncNotifier extends Notifier<HealthSyncState> {
  @override
  HealthSyncState build() => const HealthSyncState();

  Future<void> sync({int days = 45}) async {
    if (state.syncing) return;
    state = HealthSyncState(syncing: true, lastSync: state.lastSync, lastResult: state.lastResult);
    try {
      final now = ref.read(clockProvider)();
      final result = await ref.read(readinessRepositoryProvider).sync(ref.read(healthSourceProvider), now: now, days: days);
      state = HealthSyncState(lastSync: now, lastResult: result);
    } catch (e, st) {
      ErrorLog.instance.recordCaught(e, st);
      state = HealthSyncState(lastSync: state.lastSync, lastResult: state.lastResult, error: '$e');
    }
  }
}

/// Runs once at startup: moves rank-dependent state onto the current ladder.
final rankLadderMigrationProvider = FutureProvider<LadderMigration>((ref) async {
  final stats = await ref.read(achievementStatsProvider.future);
  final bodyweights = await ref.read(bodyweightTimelineProvider.future);
  return migrateRankLadder(
    db: ref.read(databaseProvider),
    stats: stats,
    defs: await GamificationRepository.loadAchievementDefs(),
    now: ref.read(clockProvider)(),
    ranksKnown: !bodyweights.isEmpty,
  );
});

/// Working sets per group: last 7 days vs. weekly average of the 4 weeks before (body-graph heatmap).
final groupVolumeProvider = Provider<Map<Muscle, GroupVolume>>((ref) {
  final history = ref.watch(historyProvider).value;
  if (history == null) return const {};
  final counts = const TrainingLoad().counts(ref.watch(clockProvider)(), groupSetEntries(history));
  return {for (final e in counts.entries) e.key: GroupVolume(recentSets: e.value.$1, weeklyAverage: e.value.$2)};
});

/// Muscle recovery now (display only; suggestions never read it). Today's readiness band scales the
/// recovery speed; while readiness is calibrating it counts as Green.
final recoveryProvider = Provider<RecoveryState?>((ref) {
  final history = ref.watch(historyProvider).value;
  if (history == null) return null;
  final r = ref.watch(todayReadinessProvider);
  return computeRecovery(history, now: ref.watch(clockProvider)(), readinessBand: r == null || r.calibrating ? null : r.band.name);
});

// ---------------------------------------------------------------------------
// Program (Min-Max Phase 2)
// ---------------------------------------------------------------------------

final programRepositoryProvider = Provider((ref) => ProgramRepository(ref.watch(databaseProvider)));

final programProvider = FutureProvider<Program>((ref) => ProgramRepository.load());


