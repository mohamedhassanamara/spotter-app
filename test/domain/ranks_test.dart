import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscle_group.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

const bench = StrengthStandard(
  id: 'bench',
  name: 'Bench press',
  exerciseIds: ['Bench'],
  thresholds: [0, 0.5, 0.75, 1.0, 1.5, 2.0, 2.3],
  targets: MuscleTargets(primary: {MuscleGroup.chest}, secondary: {MuscleGroup.shoulders, MuscleGroup.triceps}),
);

const dips = StrengthStandard(
  id: 'dips',
  name: 'Dips',
  exerciseIds: ['Dips'],
  thresholds: [0, 1.0, 1.2, 1.5, 1.8, 2.1, 2.415],
  bodyweightLoaded: true,
  targets: MuscleTargets(primary: {MuscleGroup.triceps, MuscleGroup.chest}, secondary: {MuscleGroup.shoulders}),
);

void main() {
  group('tiers and divisions', () {
    test('ratio 1.25 is halfway through Gold → Gold II', () {
      final s = bench.scoreForRatio(1.25);
      expect(s.tier, Tier.gold);
      expect(s.tierProgress, closeTo(0.5, 1e-9));
      expect(s.label, 'Gold II');
      expect(s.divisionProgress, closeTo(0.5, 1e-9));
    });

    test('exactly on a threshold is the bottom of that tier', () {
      expect(bench.scoreForRatio(0.5).label, 'Bronze III');
      expect(bench.scoreForRatio(1.0).label, 'Gold III');
    });

    test('Iron progress is linear from zero', () {
      final s = bench.scoreForRatio(0.2); // 0.4 through Iron
      expect(s.label, 'Iron II');
      expect(s.value, closeTo(0.4, 1e-9));
    });

    test('Champion runs to 125% of its entry and caps at Champion I', () {
      expect(bench.scoreForRatio(2.3).label, 'Champion III');
      expect(bench.scoreForRatio(5).label, 'Champion I');
      expect(bench.scoreForRatio(5).value, lessThan(7));
    });

    test('next threshold in kg', () {
      // Gold II at bw 80: next division (Gold I) starts at 1.0 + 0.5 × 2/3 = 1.3333 → 106.67 kg.
      final s = bench.scoreForRatio(1.25);
      expect(bench.nextThresholdKg(s, 80), closeTo(106.667, 1e-3));
      // Gold I → Platinum entry 1.5 × 80 = 120.
      expect(bench.nextThresholdKg(bench.scoreForRatio(1.4), 80), closeTo(120, 1e-9));
      expect(bench.nextThresholdKg(bench.scoreForRatio(5), 80), isNull);
    });
  });

  group('aggregation', () {
    const calc = RankCalculator([bench, dips]);

    test('muscle-group rank is the weighted average (primary 1.0, secondary 0.3)', () {
      // bw 80. Bench e1RM 100 → ratio 1.25 → 3.5. Dips e1RM 120 (bw incl.) → 1.5 → Gold III = 3.0.
      final r = calc.compute(bestE1rmByExercise: {'Bench': 100, 'Dips': 120}, bodyweight: 80);
      expect(r.exercises.length, 2);
      expect(r.groups[MuscleGroup.chest]!.score.value, closeTo(3.25, 1e-9)); // (3.5 + 3.0) / 2
      // Triceps: dips primary (1.0 × 3.0) + bench secondary (0.3 × 3.5) → 4.05 / 1.3 = 3.1154.
      expect(r.groups[MuscleGroup.triceps]!.score.value, closeTo(3.1154, 1e-4));
      // Shoulders: both secondary → plain average 3.25.
      expect(r.groups[MuscleGroup.shoulders]!.score.value, closeTo(3.25, 1e-9));
      // Overall: mean of the three groups with data.
      expect(r.overall!.value, closeTo((3.25 + 3.1154 + 3.25) / 3, 1e-4));
      expect(r.overall!.label, 'Gold III'); // 3.205 → 20% into Gold
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
        thresholds: [0, 0.5, 0.75, 1.0, 1.5, 1.75, 2.0125],
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
