import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/format.dart';
import 'package:spotter/core/widgets/common.dart' show formatClock;
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

/// One standard per muscle, all with identical anchors.
List<StrengthStandard> perMuscleStandards() => [
      for (final m in Muscle.values)
        StrengthStandard(id: m.name, name: m.label, kind: StandardKind.free, exerciseIds: [m.name], anchors: const [0.5, 0.75, 1.0, 1.4, 1.6]),
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
    final standards = perMuscleStandards();
    final calc = RankCalculator(standards);

    test('all muscles at the same tier/division → regions and overall are exactly that tier/division', () {
      const bw = 80.0;
      final points = <double>[
        for (var p = 1; p < 24; p++) ...[p.toDouble(), p + 0.5], // every division, on and inside boundaries
        24, 25.5, 28, 41, // Radiant
      ];
      for (final p in points) {
        // A 1-rep set at RPE 10 scores e1RM = load × (1 + 1/30).
        final load = standards.first.ratioForPoints(p) * bw / (1 + 1 / 30);
        final r = calc.compute(
          sets: [
            for (final m in Muscle.values)
              RankedSet(exerciseId: m.name, name: m.label, weight: load, reps: 1, rpe: 10, date: DateTime(2026, 10, 1), bodyweight: bw),
          ],
          targets: {for (final m in Muscle.values) m.name: MuscleTargets({m: 1.0})},
          currentBodyweight: bw,
        );
        final label = r.muscles.values.first.score.label;
        expect(r.muscles.length, 20);
        expect(r.rankedRegions, 6);
        expect(r.regions.values.every((g) => g.score!.label == label), isTrue, reason: 'points $p');
        expect(r.overall!.label, label, reason: 'points $p');
        expect(r.overall!.rr, r.muscles.values.first.score.rr, reason: 'points $p');
      }
    });

    test('every tier and division is reachable with the expected label', () {
      for (final t in Tier.values) {
        if (t.isApex) {
          expect(RankScore.of(t).label, t.label);
        } else {
          for (var d = 3; d >= 1; d--) {
            expect(RankScore.of(t, division: d).label, '${t.label} $d');
          }
        }
      }
    });

    test('mixed groups average on the continuous scale', () {
      final s = averageScore([RankScore(13.2), RankScore(12.8)]);
      expect(s.value, closeTo(13.0, 1e-12));
      expect(s.label, 'Platinum 2');
    });
  });
}
