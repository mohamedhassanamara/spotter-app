import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/ranks/domain/rank_history.dart';

void main() {
  final now = DateTime(2026, 10, 20, 12);
  EvolutionSample s(int daysAgo, double v) => (date: now.subtract(Duration(days: daysAgo)), value: v);

  test('the ranges: Week · Month · 3 Months · Year · All', () {
    expect([for (final r in EvolutionRange.values) r.label], ['Week', 'Month', '3 Months', 'Year', 'All']);
    expect([for (final r in EvolutionRange.values) r.days], [7, 30, 90, 365, null]);
  });

  test('a range keeps only its samples and starts at its first day, interpolated between the neighbours', () {
    final all = [s(60, 6.0), s(20, 8.0), s(10, 9.0), s(2, 10.0), s(0, 10.0)];
    final month = windowSamples(all, EvolutionRange.month, now);
    expect(month.start, now.subtract(const Duration(days: 30)));
    expect(month.samples.length, 5, reason: '4 inside plus the interpolated start');
    expect(month.samples.first.date, month.start);
    // 60 → 20 days ago goes 6 → 8: 30 days ago is 3/4 of the way... (60-30)/(60-20) = 0.75
    expect(month.samples.first.value, closeTo(6 + 2 * 0.75, 1e-9));
    final week = windowSamples(all, EvolutionRange.week, now);
    expect([for (final p in week.samples) p.value].last, 10.0);
    expect(week.samples.first.date, week.start);
    expect(week.samples.first.value, closeTo(9 + 1 * (3 / 8), 1e-9), reason: '10 → 2 days ago is 9 → 10, 7 days ago is 3/8 of the way');
  });

  test('All starts at the first sample; a range wider than the history is not padded', () {
    final all = [s(40, 6.0), s(0, 7.0)];
    final everything = windowSamples(all, EvolutionRange.all, now);
    expect(everything.samples, all);
    expect(everything.start, all.first.date);
    final year = windowSamples(all, EvolutionRange.year, now);
    expect(year.samples, all);
  });

  test('nothing inside the range: no line', () {
    final r = windowSamples([s(200, 6.0), s(150, 7.0)], EvolutionRange.month, now);
    expect(r.samples, isEmpty);
    expect(windowSamples(const [], EvolutionRange.week, now).samples, isEmpty);
  });
}
