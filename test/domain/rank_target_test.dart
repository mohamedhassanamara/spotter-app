import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/features/ranks/domain/rank_target.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

final bench = StrengthStandard(
  id: 'bench',
  name: 'Bench press',
  kind: StandardKind.free,
  exerciseIds: const ['Bench'],
  anchors: const [0.5, 0.75, 1.0, 1.4, 1.6],
);

final assistedDip = StrengthStandard(
  id: 'assisted_dip',
  name: 'Assisted dip',
  kind: StandardKind.bodyweight,
  exerciseIds: const ['sp_assisted_dip_machine'],
  anchors: const [1.0, 1.1, 1.3, 1.7, 1.8],
);

/// e1RM of [w] × [reps] at [rir] (the scorer's own formula).
double e1(double w, int reps, int rir, {double add = 0}) => scoringE1rm(load: w + add, reps: reps, rpe: 10.0 - rir);

void main() {
  final plates = WeightGrid([for (var w = 20.0; w <= 200; w += 2.5) w]);

  test('picks the lowest grid weight whose e1RM reaches the target at the minimum reps', () {
    final target = e1(72.3, 6, 1); // between grid steps
    final t = rankTargetSet(standard: bench, bodyweight: 80, targetE1rm: target, repMin: 6, rir: 1, grid: plates)!;
    expect(t.reps, 6);
    expect(t.weight, 72.5, reason: 'snapped up to the next available weight');
    expect(t.atMax, isFalse);
    expect(e1(72.5, 6, 1), greaterThanOrEqualTo(target));
    expect(e1(70, 6, 1), lessThan(target), reason: 'the weight below does not reach it');
    expect(t.text, '6 × 72.5 kg');
    expect(rankTargetLine(t, 'Gold 2'), '6 × 72.5 kg → Gold 2');
  });

  test('a target exactly on a grid weight uses that weight', () {
    final t = rankTargetSet(standard: bench, bodyweight: 80, targetE1rm: e1(60, 8, 2), repMin: 8, rir: 2, grid: plates)!;
    expect(t.weight, 60);
    expect(t.reps, 8);
  });

  test('the prescribed effort matters: the target is quoted at the prescribed reps in reserve (reps + RIR count)', () {
    final target = e1(80, 6, 0);
    final hard = rankTargetSet(standard: bench, bodyweight: 80, targetE1rm: target, repMin: 6, rir: 0, grid: plates)!;
    final easy = rankTargetSet(standard: bench, bodyweight: 80, targetE1rm: target, repMin: 6, rir: 3, grid: plates)!;
    expect(hard.weight, 80);
    expect(easy.weight, lessThan(hard.weight), reason: 'reps in reserve count towards the e1RM, so less weight reaches it');
  });

  test('above the max load: more reps at the max weight, flagged (max)', () {
    final capped = WeightGrid([for (var w = 20.0; w <= 80; w += 2.5) w], maxLoad: 80);
    final t = rankTargetSet(standard: bench, bodyweight: 80, targetE1rm: e1(80, 12, 1), repMin: 6, rir: 1, grid: capped)!;
    expect(t.weight, 80);
    expect(t.atMax, isTrue);
    expect(t.reps, 12);
    expect(t.text, '12 × 80 kg (max)');
    expect(rankTargetLine(t, 'Gold 2'), '12 × 80 kg (max) → Gold 2');
  });

  test('unreachable even with the most reps at max load: increase max load or switch variation', () {
    final capped = WeightGrid([for (var w = 20.0; w <= 40; w += 2.5) w], maxLoad: 40);
    final t = rankTargetSet(standard: bench, bodyweight: 80, targetE1rm: 200, repMin: 6, rir: 1, grid: capped);
    expect(t, isNull);
    expect(rankTargetLine(t, 'Gold 2'), 'Next rank: increase max load or switch variation');
  });

  test('no next rank, no line', () {
    expect(rankTargetLine(null, null), isNull);
  });

  test('unilateral (per-hand) lifts use the per-hand weight on a dumbbell list', () {
    final perHand = StrengthStandard(
      id: 'row',
      name: 'One-arm row',
      kind: StandardKind.free,
      exerciseIds: const ['Row'],
      anchors: const [0.2, 0.3, 0.4, 0.6, 0.7],
      perHand: true,
    );
    final dumbbells = WeightGrid(const [10, 12.5, 15, 17.5, 20, 22.5, 25, 27.5, 30, 32.5, 35]);
    final t = rankTargetSet(standard: perHand, bodyweight: 80, targetE1rm: e1(26, 8, 2), repMin: 8, rir: 2, grid: dumbbells)!;
    expect(t.weight, 27.5, reason: 'only the dumbbells that exist count');
    expect(t.reps, 8);
  });

  group('assisted and bodyweight lifts', () {
    // The logged weight is negative assistance; the load is bodyweight + that.
    final assistGrid = WeightGrid([0, for (var w = 5.0; w <= 80; w += 5) -w]);

    test('the lowest passing weight is the most assistance that still reaches it', () {
      const bw = 80.0;
      final target = e1(-20, 8, 2, add: bw);
      final t = rankTargetSet(standard: assistedDip, bodyweight: bw, targetE1rm: target, repMin: 8, rir: 2, grid: assistGrid)!;
      expect(t.weight, -20);
      expect(t.text, '8 × −20 kg');
    });

    test('between assistance steps it asks for less assistance', () {
      const bw = 80.0;
      final target = e1(-22, 8, 2, add: bw);
      final t = rankTargetSet(standard: assistedDip, bodyweight: bw, targetE1rm: target, repMin: 8, rir: 2, grid: assistGrid)!;
      expect(t.weight, -20, reason: '−20 is heavier than −22 and the next step down (−25) is too easy');
    });

    test('bodyweight with added load: 0 reads as BW', () {
      const bw = 80.0;
      final grid = WeightGrid([0, for (var w = 2.5; w <= 50; w += 2.5) w]);
      final t = rankTargetSet(standard: assistedDip, bodyweight: bw, targetE1rm: e1(0, 10, 2, add: bw), repMin: 10, rir: 2, grid: grid)!;
      expect(t.weight, 0);
      expect(t.text, '10 × BW');
    });

    test('a target beyond unassisted at the minimum reps asks for more reps at the top weight', () {
      const bw = 80.0;
      final t = rankTargetSet(standard: assistedDip, bodyweight: bw, targetE1rm: e1(0, 12, 2, add: bw), repMin: 8, rir: 2, grid: assistGrid)!;
      expect(t.weight, 0);
      expect(t.reps, 12);
      expect(t.atMax, isTrue);
    });
  });
}
