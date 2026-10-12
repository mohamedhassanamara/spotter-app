import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscle_group.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

const bench = StrengthStandard(
  id: 'bench',
  name: 'Bench press',
  exerciseIds: ['Bench'],
  thresholds: [0, 0.5, 0.75, 0.875, 1.0, 1.25, 1.4, 1.5, 1.75, 2.0],
  targets: MuscleTargets(primary: {MuscleGroup.chest}, secondary: {MuscleGroup.shoulders, MuscleGroup.triceps}),
);

const dips = StrengthStandard(
  id: 'dips',
  name: 'Dips',
  exerciseIds: ['Dips'],
  thresholds: [0, 1.0, 1.1, 1.2, 1.3, 1.5, 1.7, 1.8, 2.0, 2.2],
  bodyweightLoaded: true,
  targets: MuscleTargets(primary: {MuscleGroup.triceps, MuscleGroup.chest}, secondary: {MuscleGroup.shoulders}),
);

void main() {
  group('ladder: tiers, divisions and LP', () {
    test('5/8 of the way through Gold → Gold II, 50 LP', () {
      final s = bench.scoreForRatio(0.953125); // Gold spans 0.875–1.0
      expect(s.tier, Tier.gold);
      expect(s.value, closeTo(14.5, 1e-9));
      expect(s.label, 'Gold II');
      expect(s.lp, 50);
      expect(s.divisionProgress, closeTo(0.5, 1e-9));
    });

    test('exactly on a threshold is division IV, 0 LP', () {
      expect(bench.scoreForRatio(0.5).labelWithLp, 'Bronze IV · 0 LP');
      expect(bench.scoreForRatio(1.0).label, 'Platinum IV');
      expect(bench.scoreForRatio(1.25).label, 'Emerald IV');
    });

    test('Iron progress is linear from zero', () {
      final s = bench.scoreForRatio(0.2); // 0.4 through Iron → 1.6 points
      expect(s.label, 'Iron III');
      expect(s.lp, 60);
    });

    test('apex tiers have no divisions and LP above Master, uncapped', () {
      expect(bench.scoreForRatio(1.5).labelWithLp, 'Master · 0 LP');
      expect(bench.scoreForRatio(1.625).labelWithLp, 'Master · 200 LP');
      expect(bench.scoreForRatio(1.75).labelWithLp, 'Grandmaster · 400 LP');
      expect(bench.scoreForRatio(2.0).labelWithLp, 'Challenger · 800 LP');
      expect(bench.scoreForRatio(2.5).labelWithLp, 'Challenger · 1600 LP');
      expect(bench.scoreForRatio(2.5).divisionLabel, '');
    });

    test('next labels walk up the ladder', () {
      expect(RankScore.of(Tier.gold, division: 4).nextLabel, 'Gold III');
      expect(RankScore.of(Tier.gold, division: 1).nextLabel, 'Platinum IV');
      expect(RankScore.of(Tier.diamond, division: 1).nextLabel, 'Master');
      expect(RankScore.of(Tier.master).nextLabel, 'Grandmaster');
      expect(RankScore.of(Tier.challenger).nextLabel, isNull);
    });

    test('next threshold in kg', () {
      // Gold II at 14.5 points → Gold I starts at 15 points = 0.875 + 0.75 × 0.125 = 0.96875 → 77.5 kg at 80 kg.
      expect(bench.nextThresholdKg(bench.scoreForRatio(0.953125), 80), closeTo(77.5, 1e-9));
      // Diamond I → Master entry 1.5 × 80 = 120.
      expect(bench.nextThresholdKg(bench.scoreForRatio(1.49), 80), closeTo(120, 1e-9));
      // Master → Grandmaster entry 1.75 × 80 = 140.
      expect(bench.nextThresholdKg(bench.scoreForRatio(1.6), 80), closeTo(140, 1e-9));
      expect(bench.nextThresholdKg(bench.scoreForRatio(3), 80), isNull);
    });

    test('ratioForPoints inverts scoreForRatio', () {
      for (final p in [0.5, 3.0, 14.5, 27.9, 28.0, 30.0, 33.0, 37.5]) {
        expect(bench.scoreForRatio(bench.ratioForPoints(p)).value, closeTo(p, 1e-9));
      }
    });
  });

  group('aggregation', () {
    const calc = RankCalculator([bench, dips]);

    test('muscle-group rank is the weighted average of points (primary 1.0, secondary 0.3)', () {
      // bw 80. Bench 106 kg → 1.325 → halfway through Emerald = 22 points (Emerald II).
      // Dips 120 kg incl. bodyweight → 1.5 → Emerald IV = 20 points.
      final r = calc.compute(bestE1rmByExercise: {'Bench': 106, 'Dips': 120}, bodyweight: 80);
      expect(r.exercises.length, 2);
      expect(r.groups[MuscleGroup.chest]!.score.value, closeTo(21, 1e-9)); // (22 + 20) / 2
      expect(r.groups[MuscleGroup.chest]!.score.label, 'Emerald III');
      // Triceps: dips primary (1.0 × 20) + bench secondary (0.3 × 22) → 26.6 / 1.3 = 20.4615.
      expect(r.groups[MuscleGroup.triceps]!.score.value, closeTo(20.4615, 1e-4));
      expect(r.groups[MuscleGroup.triceps]!.score.labelWithLp, 'Emerald IV · 46 LP');
      // Shoulders: both secondary → plain average 21.
      expect(r.groups[MuscleGroup.shoulders]!.score.value, closeTo(21, 1e-9));
      // Overall: mean of the three groups' points = 20.8205 → Emerald IV, 82 LP.
      expect(r.overall!.value, closeTo((21 + 20.4615 + 21) / 3, 1e-4));
      expect(r.overall!.labelWithLp, 'Emerald IV · 82 LP');
    });

    test('unranked groups get hints, ranked ones do not', () {
      final r = calc.compute(bestE1rmByExercise: {'Bench': 100}, bodyweight: 80);
      expect(r.groups.containsKey(MuscleGroup.back), isFalse);
      expect(r.unrankedHints[MuscleGroup.back], isEmpty);
      expect(r.unrankedHints.containsKey(MuscleGroup.chest), isFalse);
    });

    test('best of several exercise ids counts for a standard', () {
      const multi = StrengthStandard(
        id: 'row',
        name: 'Row',
        exerciseIds: ['A', 'B'],
        thresholds: [0, 0.5, 0.75, 0.875, 1.0, 1.25, 1.4, 1.5, 1.75, 2.0],
        targets: MuscleTargets(primary: {MuscleGroup.back}, secondary: {}),
      );
      final r = const RankCalculator([multi]).compute(bestE1rmByExercise: {'A': 60, 'B': 80}, bodyweight: 80);
      expect(r.exercises.single.bestE1rm, 80);
    });

    test('no bodyweight → nothing ranked', () {
      final r = calc.compute(bestE1rmByExercise: {'Bench': 100}, bodyweight: 0);
      expect(r.overall, isNull);
    });
  });

  test('bundled strength standards parse and are valid', () {
    final raw = jsonDecode(File('assets/strength_standards.json').readAsStringSync()) as Map<String, dynamic>;
    final list = (raw['standards'] as List<dynamic>)
        .map((e) => StrengthStandard.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(list.length, greaterThanOrEqualTo(25));
    final covered = list.expand((s) => s.targets.primary).toSet();
    expect(covered, MuscleGroup.values.toSet(), reason: 'every group can be ranked');
  });
}
