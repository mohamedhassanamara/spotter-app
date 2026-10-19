import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';
import 'package:spotter/features/workout/data/finish_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RankCalculator calc;
  setUpAll(() async => calc = RankCalculator(await RanksRepository.loadStandards()));

  RankedSet set(String id, double kg, {String name = 'Bench'}) =>
      RankedSet(exerciseId: id, name: name, weight: kg, reps: 8, rpe: 9, date: DateTime(2026, 10, 1), bodyweight: 80);

  RankSummary summary(List<RankedSet> sets) => calc.compute(
        sets: sets,
        targets: {
          'Barbell_Bench_Press_-_Medium_Grip': const MuscleTargets({Muscle.lowerChest: 1.0, Muscle.upperChest: 0.8, Muscle.frontDelt: 0.4, Muscle.triceps: 0.4}),
          'Barbell_Squat': const MuscleTargets({Muscle.quadriceps: 1.0, Muscle.glutes: 0.7}),
        },
        currentBodyweight: 80,
      );

  const bench = 'Barbell_Bench_Press_-_Medium_Grip';

  test('an RR-only gain is a gain (but not a rank change); the order is lifts, muscles, regions, overall', () {
    final before = summary([set(bench, 60)]);
    final after = summary([set(bench, 61)]);
    final gains = FinishService.rankGains(before, after);
    expect(gains, isNotEmpty);
    expect(gains.first.scope, RankChangeScope.exercise);
    expect(gains.last.scope, RankChangeScope.overall);
    final scopes = gains.map((g) => g.scope.index).toList();
    expect([...scopes]..sort(), scopes, reason: 'lifts, then muscles, then regions, then overall');
    for (final g in gains) {
      expect(g.toScore.value, greaterThan(g.fromScore!.value));
    }
  });

  test('a first placement counts, with no from', () {
    final gains = FinishService.rankGains(summary([]), summary([set(bench, 70)]));
    final lift = gains.firstWhere((g) => g.scope == RankChangeScope.exercise);
    expect(lift.fromScore, isNull);
    expect(lift.up, isTrue);
  });

  test('no change, or a fall, is no gain', () {
    final a = summary([set(bench, 70)]);
    expect(FinishService.rankGains(a, a), isEmpty);
    expect(FinishService.rankGains(a, summary([set(bench, 60)])), isEmpty);
  });

  test('a heavy jump crosses a division: the lift is a rank-up, and so is the overall rank when its division moves', () {
    final before = summary([set(bench, 40)]);
    final after = summary([set(bench, 100)]);
    final gains = FinishService.rankGains(before, after);
    final lift = gains.firstWhere((g) => g.scope == RankChangeScope.exercise);
    expect(lift.isRankUp, isTrue);
    expect(lift.fromScore!.label, isNot(lift.toScore.label));
  });

  test('biggest gain first inside a group', () {
    final before = summary([set(bench, 60), set('Barbell_Squat', 80, name: 'Squat')]);
    final after = summary([set(bench, 62), set('Barbell_Squat', 110, name: 'Squat')]);
    final lifts = FinishService.rankGains(before, after).where((g) => g.scope == RankChangeScope.exercise).toList();
    expect(lifts.first.name, 'Squat');
  });
}
