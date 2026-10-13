import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/equipment.dart';
import '../../../core/health/fake_health_data_source.dart';
import '../../../core/settings/app_settings.dart';
import '../../coach/data/coach_context.dart';
import '../../coach/domain/guardrail.dart';
import '../../gamification/data/gamification_repository.dart';
import '../../gamification/domain/quests.dart';
import '../../gamification/domain/stats.dart';
import '../../library/domain/exercise_info.dart';
import '../../readiness/data/readiness_repository.dart';
import '../../readiness/domain/readiness.dart';
import '../../workout/data/finish_service.dart';
import '../../workout/data/history_repository.dart';
import '../../program/data/program_repository.dart';
import '../../workout/data/routine_repository.dart';
import '../../workout/data/session_repository.dart';

class SeedReport {
  const SeedReport({required this.sessions, required this.sets, required this.freezes, required this.xp});
  final int sessions;
  final int sets;
  final int freezes;
  final int xp;

  @override
  String toString() => '$sessions sessions, $sets sets, $freezes ego freezes, $xp XP';
}

/// Debug-only generator: 12 weeks of realistic PPL history, pushed through the real
/// suggestion engine and finish pipeline so XP, PRs, ranks, freezes and achievements are consistent.
class SeedGenerator {
  SeedGenerator(this._db);
  final AppDatabase _db;

  static const weeks = 12;
  static const bodyweight = 80.0;

  static const _chestPress = 'Leverage_Chest_Press';
  static const _pendulum = 'sp_pendulum_squat';

  /// Hidden starting strength (e1RM kg; bodyweight included for bodyweight-loaded lifts;
  /// per dumbbell for DB lifts) for the owner's Min-Max Phase 2 routine exercises.
  static const _startE1rm = <String, double>{
    _chestPress: 105,
    'Straight-Arm_Pulldown': 45,
    'Butterfly': 80,
    'Lying_T-Bar_Row': 80,
    'sp_db_incline_y_raise': 9,
    'Lying_Leg_Curls': 75,
    _pendulum: 150,
    'Leg_Extensions': 95,
    'sp_db_walking_lunge': 26,
    'Calf_Press_On_The_Leg_Press_Machine': 180,
    'Hyperextensions_Back_Extensions': 100,
    'Cable_Crossover': 30,
    'Smith_Machine_Overhead_Shoulder_Press': 65,
    'Smith_Machine_Bench_Press': 95,
    'Single-Leg_Leg_Extension': 45,
    'sp_standing_machine_lateral_raise': 30,
    'sp_assisted_pull_up_machine': 70,
    'Stiff-Legged_Barbell_Deadlift': 120,
    'Close-Grip_Front_Lat_Pulldown': 80,
    'One-Arm_Dumbbell_Row': 42,
    'Reverse_Machine_Flyes': 55,
    'Face_Pull': 35,
    'Decline_Crunch': 95,
    'EZ-Bar_Curl': 45,
    'Cable_Rope_Overhead_Triceps_Extension': 40,
    'Preacher_Hammer_Dumbbell_Curl': 20,
    'Triceps_Pushdown': 50,
    'Cable_Wrist_Curl': 35,
    'sp_cable_reverse_wrist_curl': 22,
    'sp_cable_lateral_raise': 13,
  };

  static const _bodyweightLoaded = {'sp_assisted_pull_up_machine', 'Decline_Crunch', 'Hyperextensions_Back_Extensions'};

  /// Ego-lifting episodes: week (0-based) → lifts overridden in every session of that week.
  /// Kept in the first half so the coach has time to rebuild after each freeze.
  static const _overrideEpisodes = <int, Set<String>>{
    // Each lift is trained once a week in the 5x split, so an episode spans two weeks
    // (the ego flag needs overrides in 2 of the last 3 sessions).
    1: {_chestPress},
    2: {_chestPress},
    4: {_pendulum},
    5: {_pendulum},
  };

  Future<void> wipeTrainingData() => _db.transaction(() async {
        await _db.delete(_db.workoutSets).go();
        await _db.delete(_db.sessionExercises).go();
        await _db.delete(_db.sessions).go();
        await _db.delete(_db.routineExercises).go();
        await _db.delete(_db.routines).go();
        await _db.delete(_db.xpEvents).go();
        await _db.delete(_db.achievementsUnlocked).go();
        await _db.delete(_db.quests).go();
        await _db.delete(_db.egoFreezes).go();
        await _db.delete(_db.dailyMetrics).go();
        await _db.delete(_db.bodyWeights).go();
      });

  Future<SeedReport> seed({
    required DateTime now,
    required Map<String, ExerciseInfo> catalog,
    required SettingsModel settings,
    void Function(String)? onProgress,
  }) async {
    final rng = math.Random(42);
    final readinessRepo = ReadinessRepository(_db);
    final routineRepo = RoutineRepository(_db);
    final sessionRepo = SessionRepository(_db);
    final historyRepo = HistoryRepository(_db);
    final freezeRepo = EgoFreezeRepository(_db);
    final gami = GamificationRepository(_db);
    final finish = FinishService(_db);
    final fake = FakeHealthDataSource(baseBodyMass: bodyweight);

    onProgress?.call('Wiping training data…');
    await wipeTrainingData();
    await _db.putSetting(SettingsModel.kFakeHealth, 'true');

    onProgress?.call('Generating 90 days of Health data…');
    await readinessRepo.sync(fake, now: now, days: 90);
    await _db.batch((b) {
      for (var i = 90; i >= 0; i -= 3) {
        final d = addDays(dateOnly(now), -i);
        b.insert(
          _db.bodyWeights,
          BodyWeightsCompanion.insert(measuredAt: DateTime(d.year, d.month, d.day, 7), kg: fake.bodyMassOn(d), source: 'health'),
        );
      }
    });
    final metricRows = await readinessRepo.allDays();
    final bandByDay = {for (final r in metricRows) r.date: r.readinessBand};

    onProgress?.call('Installing Min-Max Phase 2 routines…');
    final program = await ProgramRepository.load();
    await ProgramRepository(_db).installMyRoutines(
      program: program,
      definition: await ProgramRepository.loadMyRoutines(),
      catalog: catalog,
      settings: settings,
      now: addDays(now, -weeks * 7 - 1),
    );
    final allRoutines = await routineRepo.watchRoutines().first;
    final routineByName = {for (final r in allRoutines) r.routine.name: r};

    final strength = {..._startE1rm};
    final firstMonday = weekStart(addDays(dateOnly(now), -weeks * 7));
    final yesterday = addDays(dateOnly(now), -1);
    var sessions = 0;

    for (var day = firstMonday; !day.isAfter(yesterday); day = addDays(day, 1)) {
      // The program's week: Upper, Lower, rest, Push, Pull, Arms, rest.
      final dayName = program.weekLayout[day.weekday - 1];
      if (dayName == 'Rest') continue;
      final band = ReadinessBand.fromName(bandByDay[dayKey(day)]);
      if (band == ReadinessBand.red && rng.nextBool()) continue; // smart rest
      final weekIndex = day.difference(firstMonday).inDays ~/ 7;
      final routine = routineByName[dayName]!;

      final start = DateTime(day.year, day.month, day.day, 18).add(Duration(minutes: rng.nextInt(50) - 20));
      final history = await historyRepo.load(catalog);
      final readiness = readinessRepo.computeFor(day, metricRows);
      final coach = CoachContext(
        history: history,
        readiness: readiness,
        overloaded: const TrainingLoad().overloaded(day, groupSetEntries(history)),
        freezes: latestFreezes(await freezeRepo.all()),
        increments: settings.increments,
        now: start,
        bodyweight: bodyweight,
        bodyweightLoaded: _bodyweightLoaded,
      );
      await gami.ensureQuests(start, () => const QuestEngine().generate(QuestGenInput(
            weeklyGoal: settings.weeklyGoal,
            groupSets4w: regionSetsLast4Weeks(history, start),
            disciplinePct: disciplineLast30(history, start),
            rpeLoggedPct: rpeLoggedPct(history, start),
          )));

      final sessionId = await sessionRepo.start(
        name: routine.routine.name,
        coach: coach,
        catalog: catalog,
        routine: routine,
        program: program,
      );
      final active = (await sessionRepo.watchActive().first)!;

      var t = start.add(const Duration(minutes: 5));
      // A Red night costs about one rep of performance on every set.
      final dayPenalty = band == ReadinessBand.red ? 1.0 : 0.0;
      for (final ex in active.exercises) {
        final id = ex.row.exerciseId;
        final info = catalog[id];
        if (info == null) continue;
        final inc = settings.increments.of(info.equipmentKind);
        final bw = _bodyweightLoaded.contains(id) ? bodyweight : 0.0;
        final trueE1rm = strength[id] ?? 40;
        final sug = ex.suggestion;
        final calibration = sug?.rampUp == true;
        final overrideEpisode = (_overrideEpisodes[weekIndex]?.contains(id) ?? false) && !calibration;
        final working = ex.sets.where((s) => !s.isWarmup).toList();
        final rowRir = calibration ? 2 : ex.row.targetRir;
        var fatigue = dayPenalty;

        for (final set in ex.sets) {
          t = t.add(Duration(minutes: 2 + rng.nextInt(3)));
          if (set.isWarmup) {
            await sessionRepo.completeSet(set, weight: set.weight, reps: set.reps, rpe: null, isWarmup: true, now: t);
            continue;
          }
          final idx = working.indexOf(set);
          double weight = set.weight;
          if (calibration) {
            // Ramp towards a load the lifter can do for the bottom of the range at RPE 8.
            final target = trueE1rm / (1 + (ex.row.repMin + 2) / 30) - bw;
            weight = roundToIncrement(set.weight + (target - set.weight) * (idx + 1) / working.length, inc);
            if (!_bodyweightLoaded.contains(id)) weight = math.max(0, weight);
          } else if (overrideEpisode) {
            weight = roundToIncrement((sug?.weight ?? set.weight) * (1.10 + rng.nextDouble() * 0.05), inc);
          }

          // Reps possible at RPE 10 with this load (Epley inverted), minus accumulated fatigue.
          final load = weight + bw;
          final achievable = (load <= 0 ? 25.0 : 30 * (trueE1rm / load - 1)).clamp(0.5, 25.0) - fatigue;

          int reps;
          double? rpe;
          if (overrideEpisode) {
            reps = math.max(1, achievable.floor());
            rpe = rng.nextBool() ? 10 : 9.5;
          } else {
            // Told to stop at targetRir reps in reserve; lands within about a rep of it.
            final targetRir = set.targetRir ?? rowRir;
            final noise = rng.nextDouble() - 0.5;
            final cap = calibration ? ex.row.repMin : (set.targetRepMax ?? ex.row.repMax) + 2;
            reps = (achievable - targetRir + noise).round().clamp(1, cap).toInt();
            // Logged like a real lifter: 10 − perceived RIR, mostly whole numbers.
            final perceivedRir = (achievable - reps).round() + (rng.nextDouble() < 0.2 ? (rng.nextBool() ? 0.5 : -0.5) : 0);
            rpe = (10 - perceivedRir).clamp(6.0, 10.0).toDouble();
            if (rng.nextDouble() < 0.05) rpe = null;
          }
          fatigue += 0.5 + rng.nextDouble() * 0.3;

          final isOverride = sessionRepo.wouldOverride(set, weight);
          await sessionRepo.completeSet(
            set,
            weight: weight,
            reps: reps,
            rpe: isOverride ? (rpe ?? 9.5) : rpe,
            isWarmup: false,
            reason: isOverride ? OverrideReason.values[rng.nextInt(OverrideReason.values.length)] : null,
            now: t,
          );
        }
        // Gradual progression of the hidden strength.
        strength[id] = trueE1rm * (1 + 0.004 + rng.nextDouble() * 0.002); // +0.4–0.6 %/session
      }

      await finish.finish(
        sessionId: sessionId,
        now: t.add(const Duration(minutes: 3)),
        catalog: catalog,
        settings: settings,
      );
      sessions++;
      if (sessions % 6 == 0) onProgress?.call('Seeded $sessions sessions…');
    }

    final setCount = await _db.workoutSets.count().getSingle();
    final freezes = (await freezeRepo.all()).length;
    final xp = await gami.totalXp();
    final report = SeedReport(sessions: sessions, sets: setCount, freezes: freezes, xp: xp);
    onProgress?.call('Done: $report');
    return report;
  }
}
