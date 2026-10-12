import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/format.dart';
import 'package:spotter/core/widgets/common.dart' show formatClock;
import 'package:spotter/core/domain/muscle_group.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

/// One standard per muscle group, all with identical thresholds.
List<StrengthStandard> perGroupStandards(List<double> thresholds) => [
      for (final g in MuscleGroup.values)
        StrengthStandard(
          id: g.name,
          name: g.label,
          exerciseIds: [g.name],
          thresholds: thresholds,
          targets: MuscleTargets(primary: {g}, secondary: const {}),
        ),
    ];

void main() {
  test('clock rolls over to hours', () {
    expect(formatClock(const Duration(seconds: 95)), '1:35');
    expect(formatClock(const Duration(hours: 4, minutes: 14, seconds: 53)), '4:14:53');
    expect(formatClock(const Duration(seconds: -15)), '-0:15');
  });

  group('volume formatting', () {
    test('kg with separators below 10,000, then tonnes with one decimal', () {
      expect(formatVolume(0), '0 kg');
      expect(formatVolume(950.4), '950 kg');
      expect(formatVolume(6763), '6,763 kg');
      expect(formatVolume(9999.4), '9,999 kg');
      expect(formatVolume(10000), '10.0 t');
      expect(formatVolume(15640), '15.6 t');
      expect(formatVolume(63712), '63.7 t');
    });
  });

  group('overall rank', () {
    const thresholds = [0.0, 0.5, 0.75, 0.875, 1.0, 1.25, 1.4, 1.5, 1.75, 2.0];
    final standards = perGroupStandards(thresholds);
    final calc = RankCalculator(standards);

    test('all groups at the same tier/division → overall is exactly that tier/division', () {
      const bw = 80.0;
      final points = <double>[
        for (var p = 0; p < 28; p++) ...[p.toDouble(), p + 0.5], // every division, on and inside boundaries
        28, 29.5, 32, 33.25, 36, 41, // apex
      ];
      for (final p in points) {
        final ratio = standards.first.ratioForPoints(p).clamp(0.001, double.infinity);
        final best = {for (final g in MuscleGroup.values) g.name: ratio * bw};
        final r = calc.compute(bestE1rmByExercise: best, bodyweight: bw);
        final groupLabel = r.groups.values.first.score.label;
        expect(r.groups.length, 12);
        expect(r.groups.values.every((g) => g.score.label == groupLabel), isTrue);
        expect(r.overall!.label, groupLabel, reason: 'points $p');
        expect(r.overall!.lp, r.groups.values.first.score.lp, reason: 'points $p');
      }
    });

    test('every tier and division is reachable with the expected label', () {
      for (final t in Tier.values) {
        if (t.isApex) {
          expect(RankScore.of(t).label, t.label);
        } else {
          for (var d = 4; d >= 1; d--) {
            expect(RankScore.of(t, division: d).label, '${t.label} ${const ['', 'I', 'II', 'III', 'IV'][d]}');
          }
        }
      }
    });

    test('mixed groups average on the continuous scale', () {
      final s = averageScore([RankScore(13.2), RankScore(12.8)]);
      expect(s.value, closeTo(13.0, 1e-12));
      expect(s.label, 'Gold III');
    });
  });
}
