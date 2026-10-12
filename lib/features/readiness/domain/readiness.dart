import 'dart:math' as math;

import '../../../core/domain/dates.dart';
import '../../../core/domain/muscle_group.dart';

enum ReadinessBand {
  green('Green'),
  yellow('Yellow'),
  red('Red');

  const ReadinessBand(this.label);
  final String label;

  static ReadinessBand? fromName(String? name) {
    for (final b in values) {
      if (b.name == name) return b;
    }
    return null;
  }
}

/// Raw recovery metrics attributed to one calendar day (the night/morning before it).
class DayMetrics {
  const DayMetrics({required this.date, this.hrvMs, this.restingHr, this.sleepMinutes});

  final DateTime date;
  final double? hrvMs;
  final double? restingHr;
  final double? sleepMinutes;

  bool get hasAny => hrvMs != null || restingHr != null || sleepMinutes != null;
}

class Baseline {
  const Baseline(this.mean, this.sd, this.n);
  final double mean;
  final double sd;
  final int n;

  static Baseline? of(List<double> values) {
    if (values.isEmpty) return null;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.length < 2
        ? 0.0
        : values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / (values.length - 1);
    return Baseline(mean, math.sqrt(variance), values.length);
  }
}

class MetricReading {
  const MetricReading({this.value, this.baseline, this.z});

  final double? value;
  final Baseline? baseline;

  /// Oriented so that positive is always better. Null when the metric is unusable today.
  final double? z;

  /// Percentage difference vs baseline mean (raw orientation).
  double? get pctVsBaseline {
    final v = value, b = baseline;
    if (v == null || b == null || b.mean == 0) return null;
    return (v - b.mean) / b.mean * 100;
  }
}

class ReadinessResult {
  const ReadinessResult({
    required this.date,
    required this.score,
    required this.band,
    required this.calibrating,
    required this.baselineDays,
    required this.hrv,
    required this.restingHr,
    required this.sleep,
    required this.combinedZ,
    required this.reason,
    required this.missing,
  });

  final DateTime date;

  /// 0–100, or null when no metric is available today (neutral fallback).
  final int? score;
  final ReadinessBand band;
  final bool calibrating;
  final int baselineDays;
  final MetricReading hrv;
  final MetricReading restingHr;
  final MetricReading sleep;
  final double? combinedZ;
  final String reason;

  /// Human names of metrics missing today, e.g. ["HRV"].
  final List<String> missing;

  /// Score used by the coach: calibration and missing data fall back to neutral.
  int get coachScore => (calibrating || score == null) ? ReadinessCalculator.neutralScore : score!;
}

/// Daily readiness from HRV, resting HR and sleep vs. 30-day personal baselines.
class ReadinessCalculator {
  const ReadinessCalculator();

  static const int baselineWindowDays = 30;
  static const int calibrationDays = 14;
  static const int minBaselineSamples = 3;
  static const double weightHrv = 0.4;
  static const double weightRhr = 0.3;
  static const double weightSleep = 0.3;
  static const double shortSleepMinutes = 360;

  /// Extra negative z per hour of sleep under 6 h, regardless of baseline.
  static const double shortSleepPenaltyPerHour = 1.0;

  /// Band thresholds (shifted so that a normal day, score 60, is Green — see docs/DECISIONS.md).
  static const int greenMin = 55;
  static const int yellowMin = 40;
  static const int neutralScore = 60;

  /// Readiness penalty for an exercise whose muscle group is over its usual weekly load.
  static const int loadPenalty = 10;

  static ReadinessBand bandFor(int score) {
    if (score >= greenMin) return ReadinessBand.green;
    if (score >= yellowMin) return ReadinessBand.yellow;
    return ReadinessBand.red;
  }

  /// Piecewise-linear map of a clamped z in [-2, 2] to 0–100 with z = 0 → 60.
  static int scoreFromZ(double z) {
    final c = z.clamp(-2.0, 2.0);
    final s = c <= 0 ? 60 + c * 30 : 60 + c * 20;
    return s.round().clamp(0, 100);
  }

  ReadinessResult compute(DayMetrics today, Iterable<DayMetrics> history) {
    final day = dateOnly(today.date);
    final windowStart = addDays(day, -baselineWindowDays);
    final baselineDaysList = history.where((m) {
      final d = dateOnly(m.date);
      return !d.isBefore(windowStart) && d.isBefore(day);
    }).toList();

    final baselineDays = baselineDaysList.where((m) => m.hasAny).length;
    final calibrating = baselineDays < calibrationDays;

    Baseline? baselineOf(double? Function(DayMetrics) pick) =>
        Baseline.of([for (final m in baselineDaysList) ?pick(m)]);

    double? zOf(double? value, Baseline? b, {bool invert = false}) {
      if (value == null || b == null || b.n < minBaselineSamples) return null;
      if (b.sd <= 1e-9) return 0;
      final z = (value - b.mean) / b.sd;
      return invert ? -z : z;
    }

    final hrvB = baselineOf((m) => m.hrvMs);
    final rhrB = baselineOf((m) => m.restingHr);
    final sleepB = baselineOf((m) => m.sleepMinutes);

    final hrvZ = zOf(today.hrvMs, hrvB);
    final rhrZ = zOf(today.restingHr, rhrB, invert: true);
    double? sleepZ = zOf(today.sleepMinutes, sleepB);
    final sleepMin = today.sleepMinutes;
    if (sleepMin != null && sleepMin < shortSleepMinutes) {
      final hoursShort = (shortSleepMinutes - sleepMin) / 60;
      sleepZ = math.min(sleepZ ?? 0, 0) - hoursShort * shortSleepPenaltyPerHour;
    }

    final parts = <(double, double)>[
      if (hrvZ != null) (hrvZ, weightHrv),
      if (rhrZ != null) (rhrZ, weightRhr),
      if (sleepZ != null) (sleepZ, weightSleep),
    ];
    double? combined;
    int? score;
    if (parts.isNotEmpty) {
      final totalW = parts.fold<double>(0, (s, p) => s + p.$2);
      combined = parts.fold<double>(0, (s, p) => s + p.$1 * p.$2) / totalW;
      combined = combined.clamp(-2.0, 2.0);
      score = scoreFromZ(combined);
    }

    final hrv = MetricReading(value: today.hrvMs, baseline: hrvB, z: hrvZ);
    final rhr = MetricReading(value: today.restingHr, baseline: rhrB, z: rhrZ);
    final sleep = MetricReading(value: today.sleepMinutes, baseline: sleepB, z: sleepZ);

    final missing = <String>[
      if (today.hrvMs == null) 'HRV',
      if (today.restingHr == null) 'resting heart rate',
      if (today.sleepMinutes == null) 'sleep',
    ];

    final band = calibrating ? ReadinessBand.green : bandFor(score ?? neutralScore);
    return ReadinessResult(
      date: day,
      score: score,
      band: band,
      calibrating: calibrating,
      baselineDays: baselineDays,
      hrv: hrv,
      restingHr: rhr,
      sleep: sleep,
      combinedZ: combined,
      reason: _reason(hrv, rhr, sleep, calibrating, baselineDays, missing),
      missing: missing,
    );
  }

  String _reason(MetricReading hrv, MetricReading rhr, MetricReading sleep, bool calibrating, int baselineDays,
      List<String> missing) {
    if (missing.length == 3) return 'No recovery data for last night — using a neutral readiness.';
    final bits = <String>[];
    final hp = hrv.pctVsBaseline;
    if (hp != null && hp.abs() >= 5) {
      bits.add('HRV ${hp.abs().round()}% ${hp < 0 ? 'below' : 'above'} your baseline');
    }
    final rv = rhr.value, rb = rhr.baseline;
    if (rv != null && rb != null) {
      final d = rv - rb.mean;
      if (d.abs() >= 2) bits.add('resting HR ${d.abs().round()} bpm ${d > 0 ? 'above' : 'below'} baseline');
    }
    final sv = sleep.value;
    if (sv != null) {
      final sp = sleep.pctVsBaseline;
      if (sv < shortSleepMinutes || (sp != null && sp.abs() >= 10)) bits.add('${formatSleep(sv)} sleep');
    }
    String text;
    if (bits.isEmpty) {
      text = 'All recovery metrics close to your baseline';
    } else if (bits.length == 1) {
      text = _capitalise(bits.first);
    } else {
      text = '${_capitalise(bits.sublist(0, bits.length - 1).join(', '))} and ${bits.last}';
    }
    if (calibrating) text = 'Calibrating ($baselineDays/$calibrationDays days). $text';
    return text;
  }

  static String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// `5h40` style.
String formatSleep(double minutes) {
  final m = minutes.round();
  return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
}

/// Working sets per muscle group on a given day (primary groups only).
class GroupSetEntry {
  const GroupSetEntry({required this.date, required this.groups, required this.sets});
  final DateTime date;
  final Set<MuscleGroup> groups;
  final int sets;
}

/// Training-load modifier: groups whose last-7-day working sets exceed 1.5× the
/// weekly average of the 4 weeks before that.
class TrainingLoad {
  const TrainingLoad();

  static const double threshold = 1.5;

  Map<MuscleGroup, double> ratios(DateTime today, Iterable<GroupSetEntry> entries) {
    final day = dateOnly(today);
    final recentStart = addDays(day, -6); // last 7 days including today
    final priorStart = addDays(day, -34); // 28 days before that
    final recent = <MuscleGroup, int>{};
    final prior = <MuscleGroup, int>{};
    for (final e in entries) {
      final d = dateOnly(e.date);
      if (d.isAfter(day)) continue;
      final Map<MuscleGroup, int>? bucket =
          !d.isBefore(recentStart) ? recent : (!d.isBefore(priorStart) ? prior : null);
      if (bucket == null) continue;
      for (final g in e.groups) {
        bucket[g] = (bucket[g] ?? 0) + e.sets;
      }
    }
    final out = <MuscleGroup, double>{};
    for (final g in MuscleGroup.values) {
      final avg = (prior[g] ?? 0) / 4;
      if (avg <= 0) continue;
      out[g] = (recent[g] ?? 0) / avg;
    }
    return out;
  }

  Set<MuscleGroup> overloaded(DateTime today, Iterable<GroupSetEntry> entries) =>
      {for (final e in ratios(today, entries).entries) if (e.value > threshold) e.key};
}
