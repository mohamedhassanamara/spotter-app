import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/format.dart';
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
    const thresholds = [0.0, 0.5, 0.75, 1.0, 1.5, 2.0, 2.3];
    final calc = RankCalculator(perGroupStandards(thresholds));

    test('all groups at the same division → overall is exactly that division', () {
      const bw = 80.0;
      // Every tier and division, including exact boundaries (worst case for float error).
      for (var t = 0; t < thresholds.length; t++) {
        final lo = thresholds[t];
        final hi = t + 1 < thresholds.length ? thresholds[t + 1] : thresholds[t] * 1.25;
        for (var d = 0; d < 3; d++) {
          for (final f in [0.0, 0.5]) {
            final ratio = (lo + (hi - lo) * (d + f) / 3).clamp(0.01, double.infinity);
            final best = {for (final g in MuscleGroup.values) g.name: ratio * bw};
            final r = calc.compute(bestE1rmByExercise: best, bodyweight: bw);
            final groupLabel = r.groups.values.first.score.label;
            expect(r.groups.values.every((g) => g.score.label == groupLabel), isTrue);
            expect(r.overall!.label, groupLabel, reason: 'ratio $ratio');
          }
        }
      }
    });

    test('mixed groups average on the continuous scale', () {
      final s = averageScore([RankScore(3.2), RankScore(2.8)]);
      expect(s.value, closeTo(3.0, 1e-12));
      expect(s.label, 'Gold III');
    });
  });
}
