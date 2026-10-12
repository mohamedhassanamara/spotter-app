import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/database.dart';
import 'core/diagnostics/error_log.dart';
import 'core/domain/dates.dart';
import 'core/domain/history.dart';
import 'core/domain/muscle_group.dart';
import 'core/health/fake_health_data_source.dart';
import 'core/health/health_data_source.dart';
import 'core/health/healthkit_data_source.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers.dart';
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
import 'features/ranks/data/ranks_repository.dart';
import 'features/ranks/domain/body_regions.dart';
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

final redDaysProvider = Provider<Set<DateTime>>((ref) {
  final rows = ref.watch(dailyMetricsProvider).value ?? const [];
  return {
    for (final r in rows)
      if (r.readinessBand == ReadinessBand.red.name) parseDayKey(r.date),
  };
});

final latestBodyWeightProvider = StreamProvider<BodyWeight?>(
  (ref) => ref.watch(bodyWeightRepositoryProvider).watchLatest(),
);

final overloadedGroupsProvider = Provider<Set<MuscleGroup>>((ref) {
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
    return CoachContext(
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

// ---------------------------------------------------------------------------
// Ranks
// ---------------------------------------------------------------------------

final standardsProvider = FutureProvider<List<StrengthStandard>>((ref) => RanksRepository.loadStandards());

final bodyweightLoadedIdsProvider = FutureProvider<Set<String>>((ref) async {
  final standards = await ref.watch(standardsProvider.future);
  final catalog = await ref.watch(catalogProvider.future);
  return RanksRepository.bodyweightLoadedIds(standards, catalog);
});

final ranksProvider = FutureProvider<RankSummary>((ref) async {
  final history = await ref.watch(historyProvider.future);
  final standards = await ref.watch(standardsProvider.future);
  final bwIds = await ref.watch(bodyweightLoadedIdsProvider.future);
  final bw = ref.watch(latestBodyWeightProvider).value?.kg ?? 0;
  return RanksRepository.compute(
    history: history,
    standards: standards,
    bodyweightLoaded: bwIds,
    bodyweight: bw,
    now: ref.watch(clockProvider)(),
  );
});

// ---------------------------------------------------------------------------
// XP, streaks, quests, achievements
// ---------------------------------------------------------------------------

final totalXpProvider = StreamProvider<int>((ref) => ref.watch(gamificationRepositoryProvider).watchTotalXp());

final levelProvider = Provider<LevelInfo>((ref) => levelFor(ref.watch(totalXpProvider).value ?? 0));

final streakProvider = Provider<StreakResult?>((ref) {
  final history = ref.watch(historyProvider).value;
  if (history == null) return null;
  return const StreakCalculator().compute(
    plannedRestWeekdays: ref.watch(plannedRestWeekdaysProvider),
    sessionDays: [for (final s in history.sessions) s.startedAt],
    redDays: ref.watch(redDaysProvider),
    goal: ref.watch(currentSettingsProvider).weeklyGoal,
    now: ref.watch(clockProvider)(),
  );
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
  final settings = ref.watch(currentSettingsProvider);
  await repo.ensureQuests(now, () => const QuestEngine().generate(QuestGenInput(
        weeklyGoal: settings.weeklyGoal,
        groupSets4w: groupSetsLast4Weeks(history, now),
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
    redDays: ref.watch(redDaysProvider),
    weeklyGoal: ref.watch(currentSettingsProvider).weeklyGoal,
    now: ref.watch(clockProvider)(),
    bestTierIndex: ranks.exercises.fold<int>(-1, (m, r) => r.score.tier.index > m ? r.score.tier.index : m),
    totalXp: ref.watch(totalXpProvider).value ?? 0,
    prCount: findPrs(history, bodyweightLoaded: bwIds, bodyweight: bw).length,
    plannedRestWeekdays: ref.watch(plannedRestWeekdaysProvider),
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
final rankLadderMigrationProvider = FutureProvider<List<String>>((ref) async {
  final stats = await ref.read(achievementStatsProvider.future);
  return migrateRankLadder(
    db: ref.read(databaseProvider),
    stats: stats,
    defs: await GamificationRepository.loadAchievementDefs(),
    now: ref.read(clockProvider)(),
  );
});

/// Working sets per group: last 7 days vs. weekly average of the 4 weeks before (body-graph heatmap).
final groupVolumeProvider = Provider<Map<MuscleGroup, GroupVolume>>((ref) {
  final history = ref.watch(historyProvider).value;
  if (history == null) return const {};
  final counts = const TrainingLoad().counts(ref.watch(clockProvider)(), groupSetEntries(history));
  return {for (final e in counts.entries) e.key: GroupVolume(recentSets: e.value.$1, weeklyAverage: e.value.$2)};
});

// ---------------------------------------------------------------------------
// Program (Min-Max Phase 2)
// ---------------------------------------------------------------------------

final programRepositoryProvider = Provider((ref) => ProgramRepository(ref.watch(databaseProvider)));

final programProvider = FutureProvider<Program>((ref) => ProgramRepository.load());

/// Program week whose prescriptions sessions use. The owner doesn't follow the 12-week plan, so this
/// is always the standard hard week (see [standardProgramWeek]).
final programWeekProvider = FutureProvider<int>((ref) async => standardProgramWeek);


/// Weekdays the program schedules as rest (Wednesday and Sunday for Min-Max Phase 2): planned rest
/// for the streak, never "smart rest".
final plannedRestWeekdaysProvider = Provider<Set<int>>((ref) => ref.watch(programProvider).value?.plannedRestWeekdays ?? const {});
