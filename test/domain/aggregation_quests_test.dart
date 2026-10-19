import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/gamification/domain/achievements.dart';
import 'package:spotter/features/gamification/domain/quests.dart';
import 'package:spotter/features/library/domain/muscle_mapping.dart';
import 'package:spotter/features/readiness/domain/metrics_aggregator.dart';

void main() {
  group('daily metrics aggregation', () {
    const agg = DailyMetricsAggregator();
    final day = DateTime(2026, 4, 10);

    test('overlapping sleep from two sources is merged; HRV averaged over the sleep span', () {
      final m = agg.aggregate(
        day: day,
        asleep: [
          TimeInterval(DateTime(2026, 4, 9, 23), DateTime(2026, 4, 10, 3)),
          TimeInterval(DateTime(2026, 4, 10, 2), DateTime(2026, 4, 10, 6, 30)),
          TimeInterval(DateTime(2026, 4, 10, 14), DateTime(2026, 4, 10, 15)), // nap after noon: next day's window
        ],
        hrv: [
          TimedValue(DateTime(2026, 4, 10, 1), DateTime(2026, 4, 10, 1), 40),
          TimedValue(DateTime(2026, 4, 10, 5), DateTime(2026, 4, 10, 5), 60),
          TimedValue(DateTime(2026, 4, 10, 8), DateTime(2026, 4, 10, 8), 100), // awake: excluded
        ],
        restingHr: [
          TimedValue(DateTime(2026, 4, 9, 9), DateTime(2026, 4, 9, 9), 52),
          TimedValue(DateTime(2026, 4, 10, 7), DateTime(2026, 4, 10, 7), 54),
          TimedValue(DateTime(2026, 4, 8, 7), DateTime(2026, 4, 8, 7), 70), // too old
        ],
      );
      expect(m.sleepMinutes, 450);
      expect(m.hrvMs, 50);
      expect(m.restingHr, 53);
    });

    test('without sleep, HRV uses the last 24h', () {
      final m = agg.aggregate(
        day: day,
        asleep: const [],
        hrv: [
          TimedValue(DateTime(2026, 4, 9, 13), DateTime(2026, 4, 9, 13), 30),
          TimedValue(DateTime(2026, 4, 10, 9), DateTime(2026, 4, 10, 9), 50),
          TimedValue(DateTime(2026, 4, 9, 11), DateTime(2026, 4, 9, 11), 99), // older than 24h
        ],
        restingHr: const [],
      );
      expect(m.sleepMinutes, isNull);
      expect(m.hrvMs, 40);
      expect(m.restingHr, isNull);
    });
  });

  group('muscle mapping', () {
    test('derived defaults: dataset primary 1.0, secondary 0.3, split by keywords', () {
      final row = deriveTargets('Seated Cable Rows', ['middle back'], ['biceps', 'lats', 'shoulders']);
      expect(row.weights, {Muscle.upperBack: 1.0, Muscle.biceps: 0.3, Muscle.lats: 0.3, Muscle.rearDelt: 0.3});
      final incline = deriveTargets('Incline Cable Flye', ['chest'], ['shoulders']);
      expect(incline.weightFor(Muscle.upperChest), 1.0);
      expect(incline.weightFor(Muscle.lowerChest), 0.5);
      expect(deriveTargets('Dips - Chest Version', ['chest'], []).weightFor(Muscle.lowerChest), 1.0);
      expect(deriveTargets('Side Lateral Raise', ['shoulders'], []).primary, {Muscle.middleDelt});
      expect(deriveTargets('Face Pull', ['shoulders'], ['middle back']).primary, {Muscle.rearDelt});
      expect(deriveTargets('Russian Twist', ['abdominals'], []).primary, {Muscle.obliques});
      final press = deriveTargets('Barbell Shoulder Press', ['shoulders'], ['triceps']);
      expect(press.weights, {Muscle.frontDelt: 1.0, Muscle.middleDelt: 0.5, Muscle.triceps: 0.3});
    });

    test('hand-authored contributions win over derived ones', () {
      ExerciseMuscleTable.load(File('assets/exercise_muscles.json').readAsStringSync());
      final y = targetsFor('sp_db_incline_y_raise', 'Dumbbell Incline Y Raise', ['shoulders'], ['traps']);
      expect(y.weights, {Muscle.middleDelt: 1.0, Muscle.traps: 0.4, Muscle.rearDelt: 0.3});
      final incline = targetsFor('Barbell_Incline_Bench_Press_-_Medium_Grip', 'x', [], []);
      expect(incline.weights, {Muscle.upperChest: 1.0, Muscle.frontDelt: 0.6, Muscle.lowerChest: 0.4, Muscle.triceps: 0.3});
    });

    test('every exercise in my routines and the Liftoff name map is hand-authored', () {
      ExerciseMuscleTable.load(File('assets/exercise_muscles.json').readAsStringSync());
      final authored = ExerciseMuscleTable.ids.toSet();
      final routines = jsonDecode(File('assets/programs/my_routines.json').readAsStringSync()) as Map<String, dynamic>;
      for (final r in (routines['routines'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        for (final e in (r['exercises'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          expect(authored, contains(e['exercise_id']));
        }
      }
      final map = (jsonDecode(File('assets/liftoff_name_map.json').readAsStringSync()) as Map<String, dynamic>)['map'] as Map<String, dynamic>;
      for (final v in map.values) {
        final ids = switch (v) {
          final String id => [id],
          {'id': final String id} => [id],
          {'by_weight': final List<dynamic> rules} => [for (final r in rules) (r as Map<String, dynamic>)['id'] as String],
          _ => const <String>[],
        };
        for (final id in ids) {
          expect(authored, contains(id));
        }
      }
    });

    test('every muscle in the bundled dataset maps somewhere', () {
      final list = jsonDecode(File('assets/exercises.json').readAsStringSync()) as List<dynamic>;
      final muscles = <String>{
        for (final e in list.cast<Map<String, dynamic>>())
          ...[...(e['primaryMuscles'] as List<dynamic>), ...(e['secondaryMuscles'] as List<dynamic>)].cast<String>(),
      };
      for (final m in muscles) {
        expect(deriveTargets('x', [m], []).isEmpty, isFalse, reason: m);
      }
    });
  });

  group('weekly challenges', () {
    const engine = QuestEngine();
    final monday = DateTime(2026, 10, 12);

    test('the pool has at least 20 distinct challenges, none about following suggestions', () {
      expect(weeklyChallengePool.length, greaterThanOrEqualTo(20));
      expect({for (final q in weeklyChallengePool) q.id}.length, weeklyChallengePool.length, reason: 'ids are unique');
      for (final q in weeklyChallengePool) {
        expect(q.title.toLowerCase(), isNot(contains('suggest')), reason: q.id);
        expect(q.title.toLowerCase(), isNot(contains('coach')), reason: q.id);
        expect(q.title.toLowerCase(), isNot(contains('override')), reason: q.id);
      }
      expect(QuestKey.values.map((k) => k.name), isNot(contains('followAll')));
      expect(QuestKey.values.map((k) => k.name), isNot(contains('noOverride')));
    });

    test('three per Monday, never two of a kind, the same Monday gives the same three', () {
      final a = engine.generate(QuestGenInput(weekStart: monday, hasSleepData: true, hasReadinessData: true));
      expect(a.length, 3);
      expect({for (final q in a) q.key}.length, 3);
      expect(engine.generate(QuestGenInput(weekStart: monday, hasSleepData: true, hasReadinessData: true)).map((q) => q.id), a.map((q) => q.id));
    });

    test('they rotate: a different set each Monday, nothing repeated from last week, over many weeks the whole pool shows up', () {
      final seen = <String>{};
      var prev = <String>{};
      for (var w = 0; w < 80; w++) {
        final day = monday.add(Duration(days: 7 * w));
        final picks = engine.generate(QuestGenInput(weekStart: day, recentIds: prev, hasSleepData: true, hasReadinessData: true));
        expect(picks.map((q) => q.id).toSet().intersection(prev), isEmpty, reason: 'week $w repeats last week');
        seen.addAll(picks.map((q) => q.id));
        prev = picks.map((q) => q.id).toSet();
      }
      expect(seen.length, weeklyChallengePool.length, reason: 'every challenge comes up');
    });

    test('nothing that needs Health sleep or readiness data without it; topping up respects what is already there', () {
      for (var w = 0; w < 60; w++) {
        final picks = engine.generate(QuestGenInput(weekStart: monday.add(Duration(days: 7 * w))));
        expect(picks.map((q) => q.key), isNot(contains(QuestKey.sleep)));
        expect(picks.map((q) => q.key), isNot(contains(QuestKey.greenDay)));
      }
      final more = engine.generate(QuestGenInput(weekStart: monday, exclude: {QuestKey.sessions, QuestKey.pr}), count: 1);
      expect(more.single.key, isNot(anyOf(QuestKey.sessions, QuestKey.pr)));
    });

    ExerciseActivity ex(String id, Set<BodyRegion> g, List<int> reps, {double? rpe = 8, bool isNew = false, int warmups = 0}) => ExerciseActivity(
          exerciseId: id,
          primaryRegions: g,
          repMax: 10,
          isNew: isNew,
          sets: [
            for (var i = 0; i < warmups; i++) const LoggedSet(weight: 20, reps: 5, isWarmup: true),
            for (final r in reps) LoggedSet(weight: 80, reps: r, rpe: rpe, suggestedWeight: 50),
          ],
        );

    test('progress is measured from what was lifted, never from the suggestion', () {
      final week = QuestWeek(sleepNights: 4, sessions: [
        SessionActivity(date: DateTime(2026, 10, 12), durationMinutes: 70, readinessBand: 'green', prCount: 1, exercises: [
          ex('bench', {BodyRegion.chest}, [10, 10, 10], isNew: true, warmups: 2),
          ex('row', {BodyRegion.back}, [10, 9], rpe: 10),
        ]),
        SessionActivity(date: DateTime(2026, 10, 14), durationMinutes: 95, readinessBand: 'yellow', exercises: [
          ex('pulldown', {BodyRegion.back}, [10, 10]),
          ex('curl', {BodyRegion.arms}, [12, 12], rpe: null),
        ]),
      ]);
      int p(QuestKey k, int t, {BodyRegion? g}) => engine.progress(QuestDef(key: k, target: t, group: g), week);
      expect(p(QuestKey.sessions, 3), 2);
      expect(p(QuestKey.topOfRange, 2), 3, reason: 'bench, pulldown and curl at the top of 10');
      expect(p(QuestKey.trainGroup, 2, g: BodyRegion.back), 2);
      expect(p(QuestKey.logRpe, 3), 1);
      expect(p(QuestKey.newExercise, 1), 1);
      expect(p(QuestKey.pr, 1), 1);
      expect(p(QuestKey.workingSets, 60), 9);
      expect(p(QuestKey.warmups, 3), 1);
      expect(p(QuestKey.greenDay, 1), 1);
      expect(p(QuestKey.regions, 4), 3);
      expect(p(QuestKey.toFailure, 5), 2, reason: 'RPE 10 sets');
      expect(p(QuestKey.sleep, 5), 4);
      expect(p(QuestKey.quickSession, 1), 1, reason: 'only the 70-minute workout');
    });

    test('volume adds up the working sets', () {
      final week = QuestWeek(sessions: [
        SessionActivity(date: DateTime(2026, 10, 12), exercises: [ex('bench', {BodyRegion.chest}, [10, 10, 10])]),
        SessionActivity(date: DateTime(2026, 10, 14), exercises: [ex('row', {BodyRegion.back}, [8, 8])]),
      ]);
      expect(engine.progress(const QuestDef(key: QuestKey.volume, target: 15000), week), 80 * 30 + 80 * 16);
    });

    test('challenges saved before this version (follow every suggestion) are not loaded; others still are', () {
      expect(QuestDef.tryFromParams('followAll', {'target': 3}), isNull);
      expect(QuestDef.tryFromParams('noOverride', {'target': 3}), isNull);
      expect(retiredQuestKeys, ['followAll', 'noOverride']);
      expect(QuestDef.fromParams('trainGroup', {'target': 2, 'group': 'hamstrings'}).group, BodyRegion.legs);
      expect(QuestDef.fromParams('trainGroup', {'target': 2, 'group': 'back'}).group, BodyRegion.back);
    });

    test('params round-trip', () {
      const q = QuestDef(key: QuestKey.trainGroup, target: 2, group: BodyRegion.legs);
      final back = QuestDef.fromParams('trainGroup', jsonDecode(jsonEncode(q.toParams())) as Map<String, dynamic>);
      expect(back.title, q.title);
    });
  });

  group('achievements', () {
    final raw = jsonDecode(File('assets/achievements.json').readAsStringSync()) as Map<String, dynamic>;
    final defs = (raw['achievements'] as List<dynamic>).map((e) => AchievementDef.fromJson(e as Map<String, dynamic>)).toList();

    test('around 50 achievements, unique keys, in the six categories', () {
      expect(defs.length, inInclusiveRange(48, 60));
      expect({for (final d in defs) d.key}.length, defs.length);
      expect({for (final d in defs) d.category}, AchievementCategory.values.toSet());
    });

    test('families have bronze, silver and gold steps with rising thresholds', () {
      final families = <String, List<AchievementDef>>{};
      for (final d in defs.where((d) => d.family != null)) {
        (families[d.family!] ??= []).add(d);
      }
      expect(families.length, greaterThanOrEqualTo(10));
      for (final e in families.entries) {
        expect(e.value.map((d) => d.level), [AchievementLevel.bronze, AchievementLevel.silver, AchievementLevel.gold], reason: e.key);
        final t = e.value.map((d) => d.threshold).toList();
        expect([...t]..sort(), t, reason: '${e.key} rises');
        expect(t.toSet().length, 3, reason: e.key);
      }
      final workouts = families['Workouts']!;
      expect(workouts.map((d) => d.threshold), [25, 100, 250]);
    });

    test('nothing rewards following suggestions: no discipline, no clean-session or override metric, no such wording', () {
      for (final d in defs) {
        final text = '${d.title} ${d.description}'.toLowerCase();
        expect(text, isNot(contains('suggest')), reason: d.key);
        expect(text, isNot(contains('override')), reason: d.key);
        expect(text, isNot(contains('discipline')), reason: d.key);
        expect(text, isNot(contains('coach')), reason: d.key);
      }
      for (final retired in ['patience', 'monk_mode', 'disciplined', 'comeback']) {
        expect(defs.map((d) => d.key), isNot(contains(retired)));
      }
      expect(AchievementType.values.map((t) => t.name), isNot(anyOf(contains('discipline'), contains('cleanSessionStreak'), contains('comebacks'))));
    });

    test('unlock from stats, every category', () {
      const eval = AchievementEvaluator();
      const stats = AchievementStats(
        sessions: 120,
        longestStreakDays: 30,
        prs: 6,
        totalVolumeKg: 120000,
        totalSets: 1200,
        maxSessionVolumeKg: 11000,
        level: 11,
        bestExerciseTierIndex: 4,
        overallTierIndex: 3,
        muscleTierIndexes: [3, 3, 2, 1, 4, 3],
        regionTierIndexes: [3, 2, 2, 2, 3, 1],
        distinctExercises: 27,
        greenSessions: 26,
        longestSleepStreak: 7,
        fullProgramWeeks: 2,
      );
      final unlocked = eval.newlyUnlocked(defs, stats, {}).map((d) => d.key).toSet();
      expect(unlocked, containsAll(['first_workout', 'sessions_25', 'sessions_100', 'streak_14', 'streak_30', 'first_pr', 'pr_5']));
      expect(unlocked, containsAll(['lift_silver', 'lift_gold', 'lift_platinum', 'overall_silver', 'overall_gold']));
      expect(unlocked, contains('muscles_gold_1'));
      expect(unlocked, isNot(contains('muscles_gold_5')), reason: 'only 4 muscles are at Gold or better');
      expect(unlocked, containsAll(['volume_100t', 'sets_250', 'sets_1000', 'big_day', 'explore_10', 'explore_25', 'green_5', 'green_25', 'sleep_3', 'sleep_7', 'program_1', 'level_5', 'level_10']));
      expect(unlocked, isNot(contains('sessions_250')));
      expect(unlocked, isNot(contains('lift_diamond')));
      expect(unlocked, isNot(contains('regions_silver')), reason: 'one region is only Bronze');
    });

    test('sleep streak and full program weeks', () {
      expect(longestSleepStreak({1: 450, 2: 430, 3: 400, 4: 480, 5: 500, 6: 421}), 3);
      expect(longestSleepStreak(const {}), 0);
      expect(fullProgramWeeks([(1, 1), (1, 2), (1, 3), (2, 1), (2, 2), (3, 1), (3, 2), (3, 3), (3, null)], {1, 2, 3}), 2);
      expect(fullProgramWeeks([(1, 1)], const {}), 0);
    });
  });
}
