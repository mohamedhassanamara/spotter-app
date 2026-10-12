import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

// Thresholds: Iron 0, Bronze .5, Silver .75, Gold .875, Platinum 1.0, Emerald 1.2, Diamond 1.4,
// Master 1.6, Grandmaster 1.84, Challenger 2.08.
final bench = StrengthStandard(
  id: 'bench',
  name: 'Bench press',
  kind: StandardKind.free,
  exerciseIds: const ['Bench'],
  anchors: const [0.5, 0.75, 1.0, 1.4, 1.6],
);

// Bodyweight lift. Thresholds: 0, 1.0, 1.1, 1.2, 1.3, 1.5, 1.7, 1.8, 2.07, 2.34.
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
  group('ladder: tiers, divisions and LP', () {
    test('thresholds come from the anchors; apex tiers sit above elite', () {
      expect(bench.thresholds, [0, 0.5, 0.75, 0.875, 1.0, 1.2, 1.4, 1.6, closeTo(1.84, 1e-9), closeTo(2.08, 1e-9)]);
    });

    test('5/8 of the way through Gold → Gold II, 50 LP', () {
      final s = bench.scoreForRatio(0.953125);
      expect(s.tier, Tier.gold);
      expect(s.value, closeTo(14.5, 1e-9));
      expect(s.label, 'Gold II');
      expect(s.lp, 50);
    });

    test('exactly on a threshold is division IV, 0 LP', () {
      expect(bench.scoreForRatio(0.5).labelWithLp, 'Bronze IV · 0 LP');
      expect(bench.scoreForRatio(1.0).label, 'Platinum IV');
      expect(bench.scoreForRatio(1.4).label, 'Diamond IV');
    });

    test('Master needs the elite anchor, Challenger 30 % more', () {
      expect(bench.scoreForRatio(1.59).tier, Tier.diamond);
      expect(bench.scoreForRatio(1.6).labelWithLp, 'Master · 0 LP');
      expect(bench.scoreForRatio(1.84).tier, Tier.grandmaster);
      expect(bench.scoreForRatio(2.08).tier, Tier.challenger);
    });

    test('next labels walk up the ladder', () {
      expect(RankScore.of(Tier.gold, division: 4).nextLabel, 'Gold III');
      expect(RankScore.of(Tier.gold, division: 1).nextLabel, 'Platinum IV');
      expect(RankScore.of(Tier.diamond, division: 1).nextLabel, 'Master');
      expect(RankScore.of(Tier.challenger).nextLabel, isNull);
    });

    test('next threshold in kg', () {
      // Gold II (14.5 points) → Gold I at 15 points = 0.875 + 0.75 × 0.125 = 0.96875 → 77.5 kg at 80 kg.
      expect(bench.nextThresholdKg(bench.scoreForRatio(0.953125), 80), closeTo(77.5, 1e-9));
      expect(bench.nextThresholdKg(bench.scoreForRatio(1.59), 80), closeTo(128, 1e-9)); // Master 1.6 × 80
      expect(bench.nextThresholdKg(bench.scoreForRatio(3), 80), isNull);
    });

    test('ratioForPoints inverts scoreForRatio', () {
      for (final p in [0.5, 3.0, 14.5, 27.9, 28.0, 30.0, 33.0, 37.5]) {
        expect(bench.scoreForRatio(bench.ratioForPoints(p)).value, closeTo(p, 1e-9));
      }
    });

    test('strength score is 25 per point, 0–1000', () {
      expect(RankScore(23).strength, 575);
      expect(RankScore(28).strength, 700); // Master
      expect(RankScore(36).strength, 900); // Challenger
      expect(RankScore(55).strength, 1000);
      expect(scoreFromStrength(575).value, 23);
    });

    test('machine and cable standards are stricter by the bundled factor', () {
      final m = StrengthStandard.fromJson({
        'id': 'x',
        'name': 'X',
        'kind': 'machine',
        'exercise_ids': ['X'],
        'anchors': {'beginner': 0.5, 'novice': 0.75, 'intermediate': 1.0, 'advanced': 1.4, 'elite': 1.6},
      }, machineStrictness: 1.1);
      expect(m.thresholds[Tier.platinum.index], closeTo(1.1, 1e-9));
      expect(m.thresholds[Tier.master.index], closeTo(1.76, 1e-9));
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
      expect(light.value, closeTo(23, 1e-9)); // 108 / 80 = 1.35 → ¾ through Emerald
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
    // Bench 90 × 6 → 108 / 80 = 1.35 → 23 points. Dips +24 × 6 → 124.8 / 80 = 1.56 → 21.2 points.
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
      expect(r.muscles[Muscle.lowerChest]!.score.value, closeTo(22.4, 1e-9)); // (23 + 0.5 × 21.2) / 1.5
      expect(r.muscles[Muscle.triceps]!.score.value, closeTo((0.3 * 23 + 21.2) / 1.3, 1e-9));
      expect(r.muscles[Muscle.frontDelt]!.score.value, closeTo((0.5 * 23 + 0.4 * 21.2) / 0.9, 1e-9));
      expect(r.muscles.containsKey(Muscle.upperChest), isFalse);
    });

    test('region = mean of its ranked muscles, with X/Y ranked; overall = mean of regions', () {
      final r = run();
      final chest = r.regions[BodyRegion.chest]!;
      expect(chest.ranked, 1);
      expect(chest.total, 2);
      expect(chest.score!.value, closeTo(22.4, 1e-9));
      expect(r.regions[BodyRegion.back]!.score, isNull);
      expect(r.rankedRegions, 3);
      final expected = (22.4 + (0.3 * 23 + 21.2) / 1.3 + (0.5 * 23 + 0.4 * 21.2) / 0.9) / 3;
      expect(r.overall!.value, closeTo(expected, 1e-9));
    });

    test('muscle gap to next division: cheapest single-lift e1RM increase', () {
      // Lower chest 22.4 (Emerald II) → 23. Bench alone needs 23 + 0.6 × 1.5 = 23.9 points → 1.395 → 111.6 kg
      // (+3.6); dips alone need 21.2 + 0.6 × 1.5 / 0.5 = 23 points → 1.65 → 132 kg (+7.2). Bench wins.
      final step = muscleNextStep(run().muscles[Muscle.lowerChest]!)!;
      expect(step.rank.exerciseId, 'Bench');
      expect(step.kg, closeTo(3.6, 1e-6));
      expect(step.nextLabel, 'Emerald I');
    });

    test('hidden exercises never rank; unranked muscles get hints from my exercises', () {
      final r = run(excluded: {'Dips'});
      expect(r.exercises.map((e) => e.exerciseId), ['Bench']);
      expect(r.muscles[Muscle.triceps]!.contributions.single.rank.exerciseId, 'Bench');
      expect(r.unrankedHints[Muscle.lats], isEmpty);
    });

    test('no bodyweight → nothing ranked', () {
      final r = calc.compute(sets: [set('Bench', 90, 6, bw: 0)], targets: {'Bench': benchTargets}, currentBodyweight: 0);
      expect(r.overall, isNull);
    });
  });

  test('bundled standards parse, and every hand-authored exercise has one', () {
    final standards = RanksRepository.parseStandards(File('assets/strength_standards.json').readAsStringSync());
    final ids = {for (final s in standards) ...s.exerciseIds};
    final muscles = (jsonDecode(File('assets/exercise_muscles.json').readAsStringSync()) as Map<String, dynamic>)['exercises'] as Map<String, dynamic>;
    expect(muscles.keys.toSet().difference(ids), isEmpty);
    for (final s in standards) {
      expect(s.thresholds[Tier.challenger.index], greaterThan(s.thresholds[Tier.master.index] * 1.29), reason: s.name);
    }
    final machine = standards.firstWhere((s) => s.id == 'machine_chest_press');
    expect(machine.thresholds[Tier.platinum.index], closeTo(1.20 * 1.10, 1e-9));
  });
}
