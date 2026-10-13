import '../../../core/domain/dates.dart';

/// Bodyweight trend + nutrition from Apple Health, as the coach uses them. All thresholds here;
/// the effect on suggestions is deliberately modest (see SuggestionEngine and DECISIONS.md).
abstract final class EnergyConfig {
  /// Slope over the last 28 days, needing ≥ 4 weigh-ins spread over ≥ 14 days.
  static const int slopeWindowDays = 28;
  static const int minSlopeSpanDays = 14;
  static const int minSlopePoints = 4;

  /// kg per week: below −0.2 = losing, above +0.2 = gaining.
  static const double trendThreshold = 0.2;

  /// Losing at least this fast counts as a clear deficit.
  static const double deficitSlope = -0.25;

  /// 7-day intake ≤ 85 % of the 28-day average counts as a clear deficit (needs ≥ 4 logged days in
  /// the last 7 and ≥ 10 in the 28).
  static const double deficitIntakeRatio = 0.85;

  /// Protein below this many g per kg bodyweight gets a one-line note.
  static const double lowProteinPerKg = 1.6;
}

enum WeightTrend {
  losing('losing'),
  stable('stable'),
  gaining('gaining');

  const WeightTrend(this.label);
  final String label;
}

class DayNutrition {
  const DayNutrition(this.day, {this.kcal, this.proteinG});
  final DateTime day;
  final double? kcal;
  final double? proteinG;
}

class EnergyContext {
  const EnergyContext({
    this.avg7,
    this.slopePerWeek,
    this.kcal7,
    this.kcal28,
    this.protein7,
  });

  /// 7-day average bodyweight.
  final double? avg7;

  /// kg/week over the last 2–4 weeks; null without enough weigh-ins.
  final double? slopePerWeek;

  /// Average logged food energy, last 7 / 28 days (days with a log only).
  final double? kcal7;
  final double? kcal28;
  final double? protein7;

  static const none = EnergyContext();

  bool get hasNutrition => kcal7 != null || protein7 != null;

  WeightTrend? get trend => slopePerWeek == null
      ? null
      : slopePerWeek! < -EnergyConfig.trendThreshold
          ? WeightTrend.losing
          : (slopePerWeek! > EnergyConfig.trendThreshold ? WeightTrend.gaining : WeightTrend.stable);

  double? get proteinPerKg => protein7 == null || avg7 == null || avg7! <= 0 ? null : protein7! / avg7!;

  bool get lowProtein => proteinPerKg != null && proteinPerKg! < EnergyConfig.lowProteinPerKg;

  /// "losing 0.4 kg/week" / "eating 18 % under your 4-week average"; null when not in a clear deficit.
  String? get deficitReason {
    final reasons = <String>[
      if (slopePerWeek != null && slopePerWeek! <= EnergyConfig.deficitSlope) 'bodyweight ${slopePerWeek!.toStringAsFixed(1)} kg/week',
      if (kcal7 != null && kcal28 != null && kcal28! > 0 && kcal7! <= kcal28! * EnergyConfig.deficitIntakeRatio)
        'eating ${((1 - kcal7! / kcal28!) * 100).round()} % under your 4-week average',
    ];
    return reasons.isEmpty ? null : reasons.join(', ');
  }

  bool get deficit => deficitReason != null;

  /// One line for the readiness card.
  String describe() {
    final parts = <String>[
      if (avg7 != null) 'Bodyweight ${avg7!.toStringAsFixed(1)} kg (7-day)${trend == null ? '' : ', ${trend!.label}${slopePerWeek == null ? '' : ' ${slopePerWeek! >= 0 ? '+' : ''}${slopePerWeek!.toStringAsFixed(1)} kg/week'}'}',
      if (kcal7 != null) '${kcal7!.round()} kcal/day',
      if (proteinPerKg != null) 'protein ${proteinPerKg!.toStringAsFixed(1)} g/kg${lowProtein ? ' (low)' : ''}',
    ];
    final nutrition = hasNutrition ? '' : 'No nutrition data in Apple Health, so it isn\'t used.';
    return [if (parts.isNotEmpty) parts.join(' · '), if (nutrition.isNotEmpty) nutrition].join('\n');
  }

  static EnergyContext compute({required DateTime now, required List<(DateTime, double)> bodyweights, required List<DayNutrition> nutrition}) {
    final today = dateOnly(now);
    final from7 = addDays(today, -6), from28 = addDays(today, -27);
    final w7 = [for (final (t, kg) in bodyweights) if (!dateOnly(t).isBefore(from7) && !t.isAfter(now)) kg];
    final w28 = [for (final (t, kg) in bodyweights) if (!dateOnly(t).isBefore(from28) && !t.isAfter(now)) (t, kg)];
    double? slope;
    if (w28.length >= EnergyConfig.minSlopePoints) {
      final first = w28.map((e) => e.$1).reduce((a, b) => a.isBefore(b) ? a : b);
      final last = w28.map((e) => e.$1).reduce((a, b) => a.isAfter(b) ? a : b);
      if (last.difference(first).inDays >= EnergyConfig.minSlopeSpanDays) {
        // Least squares, x in days.
        final xs = [for (final e in w28) e.$1.difference(first).inMinutes / 1440];
        final ys = [for (final e in w28) e.$2];
        final mx = xs.reduce((a, b) => a + b) / xs.length, my = ys.reduce((a, b) => a + b) / ys.length;
        var num = 0.0, den = 0.0;
        for (var i = 0; i < xs.length; i++) {
          num += (xs[i] - mx) * (ys[i] - my);
          den += (xs[i] - mx) * (xs[i] - mx);
        }
        if (den > 0) slope = num / den * 7;
      }
    }
    double? avg(Iterable<double?> v, int minDays) {
      final xs = v.whereType<double>().toList();
      return xs.length < minDays ? null : xs.reduce((a, b) => a + b) / xs.length;
    }

    final n7 = nutrition.where((d) => !dateOnly(d.day).isBefore(from7) && !d.day.isAfter(now));
    final n28 = nutrition.where((d) => !dateOnly(d.day).isBefore(from28) && !d.day.isAfter(now));
    return EnergyContext(
      avg7: w7.isEmpty ? null : w7.reduce((a, b) => a + b) / w7.length,
      slopePerWeek: slope,
      kcal7: avg(n7.map((d) => d.kcal), 4),
      kcal28: avg(n28.map((d) => d.kcal), 10),
      protein7: avg(n7.map((d) => d.proteinG), 4),
    );
  }
}
