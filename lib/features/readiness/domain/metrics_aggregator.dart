import '../../../core/domain/dates.dart';
import 'readiness.dart';

/// A Health sample: a value over [from, to].
class TimedValue {
  const TimedValue(this.from, this.to, this.value);
  final DateTime from;
  final DateTime to;
  final double value;
}

class TimeInterval {
  const TimeInterval(this.start, this.end);
  final DateTime start;
  final DateTime end;
  Duration get duration => end.difference(start);
}

/// Turns raw Health samples into per-day metrics.
///
/// For day D:
/// - night window = [D-1 18:00, D 12:00)
/// - sleep = union of "asleep" intervals in the night window (overlapping sources merged)
/// - HRV = mean SDNN during the sleep span; if no sleep, mean over [D-1 12:00, D 12:00)
/// - resting HR = mean of samples in [D-1 00:00, D 12:00)
class DailyMetricsAggregator {
  const DailyMetricsAggregator();

  static DateTime nightStart(DateTime day) => DateTime(day.year, day.month, day.day - 1, 18);
  static DateTime nightEnd(DateTime day) => DateTime(day.year, day.month, day.day, 12);

  DayMetrics aggregate({
    required DateTime day,
    required List<TimedValue> hrv,
    required List<TimedValue> restingHr,
    required List<TimeInterval> asleep,
  }) {
    final d = dateOnly(day);
    final ns = nightStart(d), ne = nightEnd(d);

    final clipped = <TimeInterval>[];
    for (final i in asleep) {
      final s = i.start.isBefore(ns) ? ns : i.start;
      final e = i.end.isAfter(ne) ? ne : i.end;
      if (e.isAfter(s)) clipped.add(TimeInterval(s, e));
    }
    final merged = mergeIntervals(clipped);
    final sleepMinutes = merged.isEmpty
        ? null
        : merged.fold<int>(0, (sum, i) => sum + i.duration.inSeconds) / 60.0;

    List<TimedValue> hrvInWindow;
    if (merged.isNotEmpty) {
      final spanStart = merged.first.start, spanEnd = merged.last.end;
      hrvInWindow = hrv.where((v) => !v.from.isBefore(spanStart) && !v.from.isAfter(spanEnd)).toList();
    } else {
      final start = DateTime(d.year, d.month, d.day - 1, 12);
      hrvInWindow = hrv.where((v) => !v.from.isBefore(start) && v.from.isBefore(ne)).toList();
    }

    final rhrStart = DateTime(d.year, d.month, d.day - 1);
    final rhrInWindow = restingHr.where((v) => !v.from.isBefore(rhrStart) && v.from.isBefore(ne)).toList();

    return DayMetrics(
      date: d,
      hrvMs: _mean(hrvInWindow),
      restingHr: _mean(rhrInWindow),
      sleepMinutes: sleepMinutes,
    );
  }

  static double? _mean(List<TimedValue> v) =>
      v.isEmpty ? null : v.fold<double>(0, (s, x) => s + x.value) / v.length;

  static List<TimeInterval> mergeIntervals(List<TimeInterval> input) {
    if (input.isEmpty) return const [];
    final sorted = [...input]..sort((a, b) => a.start.compareTo(b.start));
    final out = <TimeInterval>[sorted.first];
    for (final i in sorted.skip(1)) {
      final last = out.last;
      if (!i.start.isAfter(last.end)) {
        if (i.end.isAfter(last.end)) out[out.length - 1] = TimeInterval(last.start, i.end);
      } else {
        out.add(i);
      }
    }
    return out;
  }
}
