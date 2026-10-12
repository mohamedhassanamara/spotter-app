import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscle_group.dart';
import 'package:spotter/features/readiness/domain/readiness.dart';

final today = DateTime(2026, 3, 20);

/// 20 baseline days: HRV alternates 50/60 (mean 55, sd 5.1299), RHR 55/57 (mean 56, sd 1.0260),
/// sleep 420/480 min (mean 450, sd 30.779).
List<DayMetrics> baseline({int days = 20, double? sleepA, double? sleepB}) => [
      for (var i = 1; i <= days; i++)
        DayMetrics(
          date: DateTime(today.year, today.month, today.day - i),
          hrvMs: i.isEven ? 50 : 60,
          restingHr: i.isEven ? 55 : 57,
          sleepMinutes: i.isEven ? (sleepA ?? 420) : (sleepB ?? 480),
        ),
    ];

void main() {
  const calc = ReadinessCalculator();

  group('baselines', () {
    test('mean and sample standard deviation', () {
      final b = Baseline.of([50, 60, 50, 60])!;
      expect(b.mean, 55);
      expect(b.sd, closeTo(5.7735, 1e-4));
      expect(b.n, 4);
    });

    test('baseline excludes today and days older than 30', () {
      final history = [
        ...baseline(),
        DayMetrics(date: today, hrvMs: 999, restingHr: 999, sleepMinutes: 999), // today: excluded
        DayMetrics(date: DateTime(2026, 2, 1), hrvMs: 999), // 47 days ago: excluded
      ];
      final r = calc.compute(DayMetrics(date: today, hrvMs: 55, restingHr: 56, sleepMinutes: 450), history);
      expect(r.hrv.baseline!.mean, 55);
      expect(r.hrv.baseline!.n, 20);
      expect(r.baselineDays, 20);
    });
  });

  group('score and bands', () {
    test('a day exactly at baseline scores 60 and is Green', () {
      final r = calc.compute(DayMetrics(date: today, hrvMs: 55, restingHr: 56, sleepMinutes: 450), baseline());
      expect(r.calibrating, isFalse);
      expect(r.combinedZ, closeTo(0, 1e-9));
      expect(r.score, 60);
      expect(r.band, ReadinessBand.green);
      expect(r.reason, 'All recovery metrics close to your baseline');
    });

    test('low HRV only: z = -0.9747, combined -0.3899 → 48 (Yellow)', () {
      final r = calc.compute(DayMetrics(date: today, hrvMs: 50, restingHr: 56, sleepMinutes: 450), baseline());
      expect(r.hrv.z, closeTo(-0.9747, 1e-4));
      expect(r.combinedZ, closeTo(-0.3899, 1e-4));
      expect(r.score, 48);
      expect(r.band, ReadinessBand.yellow);
      expect(r.reason, 'HRV 9% below your baseline');
    });

    test('everything bad clamps to z = -2 → 0 (Red)', () {
      final r = calc.compute(DayMetrics(date: today, hrvMs: 40, restingHr: 62, sleepMinutes: 300), baseline());
      expect(r.combinedZ, -2);
      expect(r.score, 0);
      expect(r.band, ReadinessBand.red);
      expect(r.reason, 'HRV 27% below your baseline, resting HR 6 bpm above baseline and 5h00 sleep');
    });

    test('everything great clamps to z = 2 → 100', () {
      final r = calc.compute(DayMetrics(date: today, hrvMs: 80, restingHr: 50, sleepMinutes: 600), baseline());
      expect(r.score, 100);
    });

    test('piecewise linear mapping', () {
      expect(ReadinessCalculator.scoreFromZ(-2), 0);
      expect(ReadinessCalculator.scoreFromZ(-1), 30);
      expect(ReadinessCalculator.scoreFromZ(0), 60);
      expect(ReadinessCalculator.scoreFromZ(1), 80);
      expect(ReadinessCalculator.scoreFromZ(2), 100);
      expect(ReadinessCalculator.scoreFromZ(5), 100);
    });

    test('band thresholds: Green ≥ 55, Yellow 40–54, Red < 40', () {
      expect(ReadinessCalculator.bandFor(55), ReadinessBand.green);
      expect(ReadinessCalculator.bandFor(54), ReadinessBand.yellow);
      expect(ReadinessCalculator.bandFor(40), ReadinessBand.yellow);
      expect(ReadinessCalculator.bandFor(39), ReadinessBand.red);
    });
  });

  group('sleep', () {
    test('5h30 vs a 7h30 baseline: z -3.899 minus 0.5 penalty → 20', () {
      final r = calc.compute(DayMetrics(date: today, hrvMs: 55, restingHr: 56, sleepMinutes: 330), baseline());
      expect(r.sleep.z, closeTo(-4.3987, 1e-4));
      expect(r.score, 20);
      expect(r.band, ReadinessBand.red);
    });

    test('under 6h is penalised even when it matches the baseline', () {
      final r = calc.compute(
        DayMetrics(date: today, hrvMs: 55, restingHr: 56, sleepMinutes: 300),
        baseline(sleepA: 300, sleepB: 300),
      );
      expect(r.sleep.z, closeTo(-1.0, 1e-9));
      expect(r.combinedZ, closeTo(-0.3, 1e-9));
      expect(r.score, 51);
    });
  });

  group('missing data', () {
    test('missing metrics are re-weighted proportionally', () {
      // Only HRV available: combined z = z_hrv = -0.9747 → 60 - 29.24 = 31.
      final r = calc.compute(DayMetrics(date: today, hrvMs: 50), baseline());
      expect(r.combinedZ, closeTo(-0.9747, 1e-4));
      expect(r.score, 31);
      expect(r.missing, ['resting heart rate', 'sleep']);
    });

    test('HRV + sleep only: weights 0.4/0.3 re-normalised', () {
      // z_hrv = -0.9747, z_sleep = 0 → (-0.9747 × 0.4) / 0.7 = -0.5570 → 60 - 16.71 = 43.
      final r = calc.compute(DayMetrics(date: today, hrvMs: 50, sleepMinutes: 450), baseline());
      expect(r.combinedZ, closeTo(-0.5570, 1e-4));
      expect(r.score, 43);
    });

    test('no data at all falls back to neutral', () {
      final r = calc.compute(DayMetrics(date: today), baseline());
      expect(r.score, isNull);
      expect(r.coachScore, 60);
      expect(r.band, ReadinessBand.green);
      expect(r.missing.length, 3);
    });
  });

  group('calibration', () {
    test('fewer than 14 baseline days → calibrating, treated as Green', () {
      final r = calc.compute(DayMetrics(date: today, hrvMs: 40, restingHr: 62, sleepMinutes: 300), baseline(days: 10));
      expect(r.calibrating, isTrue);
      expect(r.baselineDays, 10);
      expect(r.band, ReadinessBand.green);
      expect(r.coachScore, 60);
      expect(r.score, isNotNull, reason: 'raw metrics and score still shown');
      expect(r.reason, startsWith('Calibrating (10/14 days).'));
    });

    test('14 baseline days ends calibration', () {
      final r = calc.compute(DayMetrics(date: today, hrvMs: 55, restingHr: 56, sleepMinutes: 450), baseline(days: 14));
      expect(r.calibrating, isFalse);
    });
  });

  group('training-load modifier', () {
    const load = TrainingLoad();
    List<GroupSetEntry> prior(int setsPerWeek) => [
          for (final d in [10, 17, 24, 31])
            GroupSetEntry(date: DateTime(2026, 3, 20 - d), groups: {MuscleGroup.chest}, sets: setsPerWeek),
        ];

    test('16 sets this week vs 10/week average → 1.6× → overloaded', () {
      final entries = [
        ...prior(10),
        GroupSetEntry(date: DateTime(2026, 3, 16), groups: {MuscleGroup.chest}, sets: 8),
        GroupSetEntry(date: DateTime(2026, 3, 19), groups: {MuscleGroup.chest}, sets: 8),
      ];
      expect(load.ratios(today, entries)[MuscleGroup.chest], closeTo(1.6, 1e-9));
      expect(load.overloaded(today, entries), {MuscleGroup.chest});
    });

    test('exactly 1.5× is not overloaded', () {
      final entries = [...prior(10), GroupSetEntry(date: DateTime(2026, 3, 18), groups: {MuscleGroup.chest}, sets: 15)];
      expect(load.overloaded(today, entries), isEmpty);
    });

    test('no prior history → no modifier', () {
      final entries = [GroupSetEntry(date: DateTime(2026, 3, 18), groups: {MuscleGroup.back}, sets: 30)];
      expect(load.overloaded(today, entries), isEmpty);
    });
  });
}
