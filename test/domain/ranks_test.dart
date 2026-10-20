import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

// Thresholds: Iron 0, Bronze .5, Silver .75, Gold 1.0, Platinum 1.2, Diamond 1.4, Champion 1.5, Olympian 1.6,
// Immortal 2.08.
final bench = StrengthStandard(
  id: 'bench',
  name: 'Bench press',
  kind: StandardKind.free,
  exerciseIds: const ['Bench'],
  anchors: const [0.5, 0.75, 1.0, 1.4, 1.6],
);

// Bodyweight lift. Thresholds: 0, 1.0, 1.1, 1.3, 1.5, 1.7, 1.75, 1.8, 2.34.
final dips = StrengthStandard(
  id: 'dips',
  name: 'Dips',
  kind: StandardKind.bodyweight,
  exerciseIds: const ['Dips'],
  anchors: const [1.0, 1.1, 1.3, 1.7, 1.8],
);

const benchTargets = MuscleTargets({Muscle.lowerChest: 1.0, Muscle.frontDelt: 0.5, Muscle.triceps: 0.3});
const dipTargets = MuscleTargets({Muscle.triceps: 1.0, Muscle.lowerChest: 0.5, Muscle.frontDelt: 0.4});

RankedSet set(String id, double w, int reps, {double bw = 80, double rpe = 10, DateTime? at}) => RankedSet(
      exerciseId: id,
      name: id,
      weight: w,
      reps: reps,
      rpe: rpe,
      date: at ?? DateTime(2026, 10, 1),
      bodyweight: bw,
    );

void main() {
  group('ladder: tiers, divisions and RR', () {
    test('thresholds come from the anchors: elite is Olympian, Immortal sits 30 % above', () {
      expect(bench.thresholds, [0, 0.5, 0.75, 1.0, 1.2, 1.4, 1.5, 1.6, closeTo(2.08, 1e-9)]);
    });

    test('half way through Gold → Gold 2, 50 RR', () {
      final s = bench.scoreForRatio(1.1);
      expect(s.tier, Tier.gold);
      expect(s.value, closeTo(10.5, 1e-9));
      expect(s.label, 'Gold 2');
      expect(s.rr, 50);
    });

    test('exactly on a threshold is division 1, 0 RR', () {
      expect(bench.scoreForRatio(0.5).labelWithRr, 'Bronze 1 · 0 RR');
      expect(bench.scoreForRatio(1.0).label, 'Gold 1');
      expect(bench.scoreForRatio(1.4).label, 'Diamond 1');
    });

    test('Olympian needs the elite anchor, Immortal 30 % more', () {
      expect(bench.scoreForRatio(1.59).tier, Tier.champion);
      expect(bench.scoreForRatio(1.6).labelWithRr, 'Olympian 1 · 0 RR');
      expect(bench.scoreForRatio(2.08).tier, Tier.immortal);
      expect(bench.scoreForRatio(2.08).label, 'Immortal');
      expect(bench.scoreForRatio(2.08 + (2.08 - 1.6) / 3 * 0.5).rr, 50, reason: 'Immortal RR is uncapped');
      expect(bench.scoreForRatio(4).rr, greaterThan(100));
    });

    test('three divisions per tier, 1 lowest, 3 highest; Immortal has none', () {
      expect([for (var d = 1; d <= 3; d++) RankScore.of(Tier.silver, division: d).label], ['Silver 1', 'Silver 2', 'Silver 3']);
      expect(RankScore.of(Tier.iron).value, 0);
      expect(RankScore.of(Tier.olympian, division: 3).value, closeTo(23, 1e-9));
      expect(RankScore.of(Tier.immortal, rr: 40).value, closeTo(24.4, 1e-9));
      expect(RankScore.of(Tier.immortal, rr: 40).label, 'Immortal');
      expect(RankScore(24.4).divisionLabel, '');
      expect(Tier.values.map((t) => t.label), ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Champion', 'Olympian', 'Immortal']);
    });

    test('next labels walk up the ladder', () {
      expect(RankScore.of(Tier.gold, division: 1).nextLabel, 'Gold 2');
      expect(RankScore.of(Tier.gold, division: 3).nextLabel, 'Platinum 1');
      expect(RankScore.of(Tier.olympian, division: 3).nextLabel, 'Immortal');
      expect(RankScore.of(Tier.immortal).nextLabel, isNull);
    });

    test('next threshold in kg', () {
      // Gold 2 (10.5 points) → Gold 3 at 11 points = 1.0 + (2/3) × 0.2 = 1.1333 → 90.67 kg at 80 kg.
      expect(bench.nextThresholdKg(bench.scoreForRatio(1.1), 80), closeTo((1.0 + 2 / 3 * 0.2) * 80, 1e-9));
      expect(bench.nextThresholdKg(bench.scoreForRatio(1.59), 80), closeTo(128, 1e-9)); // Olympian 1.6 × 80
      expect(bench.nextThresholdKg(bench.scoreForRatio(3), 80), isNull);
    });

    test('ratioForPoints inverts scoreForRatio', () {
      for (final p in [0.5, 3.0, 10.5, 20.9, 21.0, 24.0, 26.5, 30.0]) {
        expect(bench.scoreForRatio(bench.ratioForPoints(p)).value, closeTo(p, 1e-9));
      }
    });

    test('strength score is 37.5 per point, 0–1000', () {
      expect(RankScore(12).strength, 450);
      expect(RankScore(21).strength, 788); // Olympian
      expect(RankScore(24).strength, 900); // Immortal
      expect(RankScore(55).strength, 1000);
      expect(scoreFromStrength(450).value, 12);
    });

    test('machine and cable standards are stricter by the bundled factor', () {
      final m = StrengthStandard.fromJson({
        'id': 'x',
        'name': 'X',
        'kind': 'machine',
        'exercise_ids': ['X'],
        'anchors': {'beginner': 0.5, 'novice': 0.75, 'intermediate': 1.0, 'advanced': 1.4, 'elite': 1.6},
      }, machineStrictness: 1.1);
      expect(m.thresholds[Tier.gold.index], closeTo(1.1, 1e-9));
      expect(m.thresholds[Tier.platinum.index], closeTo(1.32, 1e-9));
      expect(m.thresholds[Tier.olympian.index], closeTo(1.76, 1e-9));
    });
  });

  group('per-set scoring', () {
    final calc = RankCalculator([bench, dips]);

    test('reps + RIR above 20 count as 20', () {
      expect(scoringE1rm(load: 100, reps: 30, rpe: 10), closeTo(100 * (1 + 20 / 30), 1e-9));
      expect(scoringE1rm(load: 100, reps: 8, rpe: 8), closeTo(100 * (1 + 10 / 30), 1e-9));
    });

    test('the same set scores lower at a heavier bodyweight (as in Liftoff)', () {
      final light = calc.scoreSet(exerciseId: 'Bench', set: set('Bench', 90, 6), bodyweight: 80)!;
      final heavy = calc.scoreSet(exerciseId: 'Bench', set: set('Bench', 90, 6), bodyweight: 100)!;
      expect(light.value, closeTo(14.25, 1e-9)); // 108 / 80 = 1.35 → ¾ through Platinum
      expect(heavy.value, lessThan(light.value));
    });

    test('bodyweight lifts include bodyweight; assistance is negative load', () {
      // 80 − 30 assistance = 50 kg × 1.2 = 60 → 0.75 bw.
      final s = calc.scoreSet(exerciseId: 'Dips', set: set('Dips', -30, 6), bodyweight: 80)!;
      expect(s.value, lessThan(4));
    });

    test('bodyweight timeline: linear between weigh-ins, flat outside', () {
      final t = BodyweightTimeline([(DateTime(2026, 4, 19), 108.0), (DateTime(2026, 10, 11), 106.0)]);
      expect(t.at(DateTime(2026, 1, 1)), 108);
      expect(t.at(DateTime(2026, 12, 1)), 106);
      expect(t.at(DateTime(2026, 7, 15, 12)), closeTo(107, 0.02));
      expect(t.latest, 106);
    });
  });

  group('muscles, regions, overall', () {
    final calc = RankCalculator([bench, dips]);
    // Bench 90 × 6 → 108 / 80 = 1.35 → 14.25 points. Dips +24 × 6 → 124.8 / 80 = 1.56 → 12.9 points.
    RankSummary run({Set<String> excluded = const {}}) => calc.compute(
          sets: [set('Bench', 90, 6), set('Bench', 80, 6), set('Dips', 24, 6)],
          targets: {'Bench': benchTargets, 'Dips': dipTargets},
          currentBodyweight: 80,
          excluded: excluded,
          hintNames: {'Bench': 'Bench', 'Dips': 'Dips', 'Row': 'Row'},
        );

    test('best set per exercise; muscle = weighted average by contribution', () {
      final r = run();
      expect(r.exercises.length, 2);
      expect(r.exercises.firstWhere((e) => e.exerciseId == 'Bench').weight, 90);
      expect(r.muscles[Muscle.lowerChest]!.score.value, closeTo(13.8, 1e-9)); // (14.25 + 0.5 × 12.9) / 1.5
      expect(r.muscles[Muscle.triceps]!.score.value, closeTo((0.3 * 14.25 + 12.9) / 1.3, 1e-9));
      expect(r.muscles[Muscle.frontDelt]!.score.value, closeTo((0.5 * 14.25 + 0.4 * 12.9) / 0.9, 1e-9));
      expect(r.muscles.containsKey(Muscle.upperChest), isFalse);
    });

    test('region = mean of its ranked muscles, with X/Y ranked; overall = mean of regions', () {
      final r = run();
      final chest = r.regions[BodyRegion.chest]!;
      expect(chest.ranked, 1);
      expect(chest.total, 2);
      expect(chest.score!.value, closeTo(13.8, 1e-9));
      expect(r.regions[BodyRegion.back]!.score, isNull);
      expect(r.rankedRegions, 3);
      final expected = (13.8 + (0.3 * 14.25 + 12.9) / 1.3 + (0.5 * 14.25 + 0.4 * 12.9) / 0.9) / 3;
      expect(r.overall!.value, closeTo(expected, 1e-9));
    });

    test('muscle gap to next division: cheapest single-lift e1RM increase', () {
      // Lower chest 13.8 (Platinum 2) → 14. Bench alone needs 14.25 + 0.2 × 1.5 = 14.55 points → 1.37 → 109.6 kg
      // (+1.6); dips alone need 12.9 + 0.2 × 1.5 / 0.5 = 13.5 points → 1.6 → 128 kg (+3.2). Bench wins.
      final step = muscleNextStep(run().muscles[Muscle.lowerChest]!)!;
      expect(step.rank.exerciseId, 'Bench');
      expect(step.kg, closeTo(1.6, 1e-6));
      expect(step.nextLabel, 'Platinum 3');
    });

    test('hidden exercises never rank; unranked muscles get hints from my exercises', () {
      final r = run(excluded: {'Dips'});
      expect(r.exercises.map((e) => e.exerciseId), ['Bench']);
      expect(r.muscles[Muscle.triceps]!.contributions.single.rank.exerciseId, 'Bench');
      expect(r.unrankedHints[Muscle.lats], isEmpty);
      // Still scored so its row can show with the switch off; it feeds nothing.
      expect(r.hidden.map((x) => x.exerciseId), ['Dips']);
      expect(run().hidden, isEmpty);
    });

    test('no bodyweight → nothing ranked', () {
      final r = calc.compute(sets: [set('Bench', 90, 6, bw: 0)], targets: {'Bench': benchTargets}, currentBodyweight: 0);
      expect(r.overall, isNull);
    });
  });

  group('allometric scaling', () {
    final scaled = StrengthStandard(
      id: 'b',
      name: 'Bench',
      kind: StandardKind.free,
      exerciseIds: const ['B'],
      anchors: const [0.5, 0.75, 1.0, 1.4, 1.6],
      scaling: BodyweightScaling.allometric,
    );

    test('scaled ratio = e1RM / (100 × (bw/100)^0.67); equals the plain ratio at 100 kg', () {
      expect(scaled.ratioFor(100, 100), closeTo(1.0, 1e-12));
      expect(scaled.ratioFor(100, 120), closeTo(100 / (100 * math.pow(1.2, 0.67)), 1e-12));
      expect(scaled.normalizer(80), closeTo(100 * math.pow(0.8, 0.67), 1e-12));
    });

    test('heavier lifters are not penalised for not lifting in proportion to bodyweight', () {
      // 1.5 × the load at 1.5 × the bodyweight scores higher than the lighter lifter's ratio would.
      final light = scaled.scoreForRatio(scaled.ratioFor(100, 80));
      final heavy = scaled.scoreForRatio(scaled.ratioFor(150, 120));
      expect(heavy.value, greaterThan(light.value));
      // With plain ratios the two would tie.
      expect(150 / 120, closeTo(100 / 80, 1e-12));
    });

    test('bodyweight lifts keep the plain ratio', () {
      final dip = StrengthStandard(
        id: 'd',
        name: 'Dip',
        kind: StandardKind.bodyweight,
        exerciseIds: const ['D'],
        anchors: const [1.0, 1.1, 1.3, 1.7, 1.8],
        scaling: BodyweightScaling.allometric,
      );
      expect(dip.ratioFor(120, 100), closeTo(1.2, 1e-12));
      expect(dip.ratioFor(144, 120), closeTo(1.2, 1e-12));
    });

    test('next-division kg inverts the scaling', () {
      final s = scaled.scoreForRatio(scaled.ratioFor(90, 110));
      final kg = scaled.nextThresholdKg(s, 110)!;
      expect(scaled.scoreForRatio(scaled.ratioFor(kg, 110)).value, closeTo((s.value + 1e-9).floorToDouble() + 1, 1e-6));
    });
  });

  test('bundled standards: every exercise covered, accessories are base compound × factor', () {
    final raw = jsonDecode(File('assets/strength_standards.json').readAsStringSync()) as Map<String, dynamic>;
    final standards = RanksRepository.parseStandards(File('assets/strength_standards.json').readAsStringSync());
    final ids = {for (final s in standards) ...s.exerciseIds};
    final muscles = (jsonDecode(File('assets/exercise_muscles.json').readAsStringSync()) as Map<String, dynamic>)['exercises'] as Map<String, dynamic>;
    expect(muscles.keys.toSet().difference(ids), isEmpty);
    final bases = raw['bases'] as Map<String, dynamic>;
    for (final j in (raw['standards'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final anchors = j['anchors'] as Map<String, dynamic>;
      if (j['kind'] == 'bodyweight') {
        expect(j.containsKey('base'), isFalse, reason: j['name'] as String);
        continue;
      }
      final base = bases[j['base']] as Map<String, dynamic>;
      for (final k in anchors.keys) {
        expect((anchors[k] as num).toDouble(), closeTo((base[k] as num) * (j['factor'] as num), 1e-3), reason: '${j['name']} $k');
      }
    }
    for (final s in standards) {
      expect(s.thresholds[Tier.immortal.index], greaterThan(s.thresholds[Tier.olympian.index] * 1.29), reason: s.name);
      expect(s.scaling.exponent, 0.67);
    }
    final machine = standards.firstWhere((s) => s.id == 'machine_chest_press');
    expect(machine.thresholds[Tier.gold.index], closeTo(1.15 * 1.05 * 1.10, 1e-3));
  });
}
