import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/features/ranks/domain/bodyweight_what_if.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

StrengthStandard std(StandardKind kind, {BodyweightScaling scaling = BodyweightScaling.linear, List<double> anchors = const [0.5, 0.75, 1.0, 1.4, 1.6]}) =>
    StrengthStandard(id: 'x', name: 'X', kind: kind, exerciseIds: const ['X'], anchors: anchors, scaling: scaling);

ExerciseRank rankOf(StrengthStandard s, {required double weight, required int reps, required double bw}) {
  final e = scoringE1rm(load: weight + (s.bodyweightLoaded ? bw : 0), reps: reps, rpe: 8);
  return ExerciseRank(
    exerciseId: 'X',
    name: 'X',
    standard: s,
    score: s.scoreForRatio(s.ratioFor(e, bw)),
    bestE1rm: e,
    bodyweight: bw,
    weight: weight,
    reps: reps,
    rpe: 8,
    date: DateTime(2026, 1, 1),
    targets: MuscleTargets.empty,
    nextThresholdKg: null,
  );
}

void main() {
  group('solveBodyweight', () {
    test('finds the lowest bodyweight whose score reaches the target, rounded up to 0.5 kg', () {
      // Rising score: 0.1 point per kg above 100.
      final t = solveBodyweight(score: (bw) => (bw - 100) * 0.1, target: 0.52, current: 100);
      expect(t.outcome, BodyweightOutcome.reachable);
      expect(t.bodyweight, 105.5, reason: '105.2 rounds up to the next half kilo');
    });

    test('already at the target at the current bodyweight', () {
      final t = solveBodyweight(score: (bw) => 5, target: 4, current: 90);
      expect(t, const BodyweightTarget(BodyweightOutcome.reachable, 90));
    });

    test('beyond +10% is not reachable', () {
      final t = solveBodyweight(score: (bw) => (bw - 100) * 0.1, target: 1.5, current: 100);
      expect(t.outcome, BodyweightOutcome.unreachable);
    });

    test('exactly at the +10% edge still counts', () {
      final t = solveBodyweight(score: (bw) => (bw - 100) * 0.1, target: 1.0, current: 100);
      expect(t.outcome, BodyweightOutcome.reachable);
      expect(t.bodyweight, 110);
    });

    test('a flat score (bodyweight does not matter) is not reachable', () {
      expect(solveBodyweight(score: (bw) => 3, target: 4, current: 100).outcome, BodyweightOutcome.unreachable);
    });

    test('no bodyweight: nothing to project', () {
      expect(solveBodyweight(score: (bw) => bw, target: 1, current: 0), BodyweightTarget.none);
    });
  });

  group('bodyweightTargetFor', () {
    test('allometric loaded lift: lighter would help, heavier is worse', () {
      final s = std(StandardKind.free, scaling: BodyweightScaling.allometric);
      final r = rankOf(s, weight: 80, reps: 6, bw: 100);
      final t = bodyweightTargetFor(r, 100);
      expect(t.outcome, BodyweightOutcome.worse);
      expect(bodyweightTargetLine(r, t, 'Next'), bodyweightWorse);
      expect(r.atBodyweight(105).score.value, lessThan(r.score.value));
    });

    test('assisted exercise: more bodyweight shrinks the assistance share, so the solve lands on a heavier weight', () {
      final s = std(StandardKind.bodyweight, anchors: const [0.3, 0.4, 0.5, 0.7, 0.8]);
      // Assistance of 50 kg: effective load = bw − 50, so each kg of bodyweight is worth more than a kg of the load.
      final r = rankOf(s, weight: -50, reps: 8, bw: 100);
      final t = bodyweightTargetFor(r, 100);
      expect(t.outcome, BodyweightOutcome.reachable);
      final bw = t.bodyweight!;
      expect(bw, greaterThan(100));
      expect(bw, lessThanOrEqualTo(110));
      final next = (r.score.value + 1e-9).floorToDouble() + 1;
      expect(r.atBodyweight(bw).score.value, greaterThanOrEqualTo(next - 1e-9), reason: 'the answer reaches the next rank');
      expect(r.atBodyweight(bw - 0.5).score.value, lessThan(next), reason: 'and is the lowest 0.5 kg that does');
      expect(bodyweightTargetLine(r, t, 'Gold 2'), 'Your 8 × −50 kg at ${bw.toString().replaceAll(RegExp(r'\.0$'), '')} kg bodyweight → Gold 2');
    });

    test('plain-ratio bodyweight lift with a bodyweight set (pull-ups): the ratio does not move', () {
      final s = std(StandardKind.bodyweight, anchors: const [0.8, 1.0, 1.3, 1.7, 2.0]);
      final r = rankOf(s, weight: 0, reps: 8, bw: 100);
      expect(r.atBodyweight(95).score.value, closeTo(r.score.value, 1e-9));
      expect(bodyweightTargetFor(r, 100).outcome, BodyweightOutcome.unreachable);
      expect(bodyweightTargetLine(r, bodyweightTargetFor(r, 100), 'Next'), bodyweightUnreachable);
    });

    test('plain-ratio weighted dip: added weight is diluted by more bodyweight, so heavier is worse', () {
      final s = std(StandardKind.bodyweight, anchors: const [0.8, 1.0, 1.3, 1.7, 2.0]);
      final r = rankOf(s, weight: 20, reps: 6, bw: 100);
      expect(bodyweightTargetFor(r, 100).outcome, BodyweightOutcome.worse);
    });

    test('top of the ladder has no target', () {
      final s = std(StandardKind.free);
      final r = rankOf(s, weight: 200, reps: 10, bw: 80);
      expect(r.score.isApex, isTrue);
      expect(bodyweightTargetFor(r, 80), BodyweightTarget.none);
    });
  });

  group('whatIf ranges', () {
    test('±10% around the current bodyweight', () {
      final r = whatIfRange(100);
      expect(r.min, closeTo(90, 1e-9));
      expect(r.max, closeTo(110, 1e-9));
    });

    test('slider bounds snap inward to 0.5 kg', () {
      final r = whatIfSliderRange(101.3);
      expect(r.min, 91.5);
      expect(r.max, 111.0);
    });
  });

  group('RankSummary.atBodyweight', () {
    final bench = StrengthStandard(id: 'b', name: 'Bench', kind: StandardKind.free, exerciseIds: const ['Bench'], anchors: const [0.5, 0.75, 1.0, 1.4, 1.6]);
    final calc = RankCalculator([bench]);
    final summary = calc.compute(
      sets: [RankedSet(exerciseId: 'Bench', name: 'Bench', weight: 100, reps: 5, rpe: 8, date: DateTime(2026, 1, 1), bodyweight: 100)],
      targets: {'Bench': MuscleTargets.empty},
      currentBodyweight: 100,
    );

    test('at the set\'s own bodyweight it reproduces the real rank', () {
      final p = summary.atBodyweight(100);
      expect(p.exercises.single.score.value, closeTo(summary.exercises.single.score.value, 1e-9));
    });

    test('a heavier lifter with the same lift ranks lower, a lighter one higher; the original is untouched', () {
      final before = summary.exercises.single.score.value;
      expect(summary.atBodyweight(110).exercises.single.score.value, lessThan(before));
      expect(summary.atBodyweight(90).exercises.single.score.value, greaterThan(before));
      expect(summary.exercises.single.score.value, before);
    });
  });

  test('BodyweightTimeline.recentAverage averages the last 7 days, else the latest', () {
    final now = DateTime(2026, 6, 10);
    final tl = BodyweightTimeline([
      (DateTime(2026, 5, 1), 90.0),
      (DateTime(2026, 6, 5), 100.0),
      (DateTime(2026, 6, 9), 102.0),
    ]);
    expect(tl.recentAverage(now), 101);
    expect(tl.recentAverage(DateTime(2026, 7, 20)), 102, reason: 'nothing in the last 7 days: the latest');
  });
}
