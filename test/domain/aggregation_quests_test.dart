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

  group('quests', () {
    const engine = QuestEngine();

    test('generation picks the least-trained group and a discipline quest', () {
      final q = engine.generate(QuestGenInput(
        weeklyGoal: 6,
        groupSets4w: {
          for (final g in BodyRegion.values) g: 40,
          BodyRegion.arms: 12,
        },
        disciplinePct: 70,
        rpeLoggedPct: 100,
      ));
      expect(q.map((e) => e.key), [QuestKey.topOfRange, QuestKey.trainGroup, QuestKey.followAll]);
      expect(q[1].group, BodyRegion.arms);
      expect(q[1].title, 'Train arms twice');
    });

    test('disciplined lifters get an RPE or no-override quest instead', () {
      final base = QuestGenInput(weeklyGoal: 6, groupSets4w: const {}, disciplinePct: 95, rpeLoggedPct: 50);
      expect(engine.generate(base)[2].key, QuestKey.logRpe);
      expect(engine.generate(base)[1].group, BodyRegion.back);
      final q = engine.generate(QuestGenInput(weeklyGoal: 6, groupSets4w: const {}, disciplinePct: 95, rpeLoggedPct: 95));
      expect(q[2].key, QuestKey.noOverride);
      expect(q[2].target, 5);
    });

    test('progress', () {
      ExerciseActivity ex(String id, Set<BodyRegion> g, List<int> reps, {bool override = false, double? rpe = 8}) =>
          ExerciseActivity(
            exerciseId: id,
            primaryRegions: g,
            repMax: 10,
            sets: [
              for (final r in reps)
                LoggedSet(weight: override ? 90 : 80, reps: r, rpe: rpe, suggestedWeight: 80, isOverride: override),
            ],
          );
      final week = [
        SessionActivity(date: DateTime(2026, 4, 6), exercises: [
          ex('bench', {BodyRegion.chest}, [10, 10, 10]),
          ex('row', {BodyRegion.back}, [10, 9]),
        ]),
        SessionActivity(date: DateTime(2026, 4, 8), exercises: [
          ex('pulldown', {BodyRegion.back}, [10, 10], override: true),
          ex('curl', {BodyRegion.arms}, [12, 12], rpe: null),
        ]),
      ];
      expect(engine.progress(const QuestDef(key: QuestKey.topOfRange, target: 2), week), 3);
      expect(engine.progress(const QuestDef(key: QuestKey.trainGroup, target: 2, group: BodyRegion.back), week), 2);
      expect(engine.progress(const QuestDef(key: QuestKey.followAll, target: 3), week), 1);
      expect(engine.progress(const QuestDef(key: QuestKey.logRpe, target: 3), week), 1);
      expect(engine.progress(const QuestDef(key: QuestKey.noOverride, target: 3), week), 1);
    });

    test('quests saved before v2.1 with an old group name still load', () {
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
    test('Patience counts consecutive sessions without overrides', () {
      expect(longestCleanStreak([false, false, true, false, false, false]), 3);
      expect(longestCleanStreak(const []), 0);
    });

    test('Comeback: deload then regain the pre-deload best', () {
      ExerciseSessionLog l(double w, int reps, SuggestionKind k) => ExerciseSessionLog(
            sessionId: 0,
            date: DateTime(2026),
            suggestionKind: k,
            sets: [LoggedSet(weight: w, reps: reps, rpe: 8)],
          );
      final comeback = [
        l(100, 8, SuggestionKind.addReps), // e1RM 133.3
        l(90, 8, SuggestionKind.plateauDeload),
        l(95, 8, SuggestionKind.increase),
        l(100, 8, SuggestionKind.increase), // regained
      ];
      final noComeback = comeback.sublist(0, 3);
      expect(countComebacks([comeback, noComeback]), 1);
    });

    test('bundled definitions parse and unlock from stats', () {
      final raw = jsonDecode(File('assets/achievements.json').readAsStringSync()) as Map<String, dynamic>;
      final defs = (raw['achievements'] as List<dynamic>)
          .map((e) => AchievementDef.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(defs.length, greaterThanOrEqualTo(15));
      const eval = AchievementEvaluator();
      const stats = AchievementStats(sessions: 12, longestCleanSessionStreak: 10, smartRestDays: 5, prs: 1);
      final unlocked = eval.newlyUnlocked(defs, stats, {'first_workout'}).map((d) => d.key).toSet();
      expect(unlocked, {'ten_workouts', 'patience', 'smart_rest', 'first_pr'});
    });

    test('discipline needs 50 sets', () {
      const few = AchievementStats(disciplinePct30: 100, workingSets30: 20);
      const many = AchievementStats(disciplinePct30: 92, workingSets30: 60);
      expect(few.valueFor(AchievementType.discipline), 0);
      expect(many.valueFor(AchievementType.discipline), 92);
    });
  });
}
