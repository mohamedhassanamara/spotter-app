import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/dates.dart';
import '../../../core/health/health_data_source.dart';
import '../domain/metrics_aggregator.dart';
import '../domain/readiness.dart';

DayMetrics dayMetricsFromRow(DailyMetric r) =>
    DayMetrics(date: parseDayKey(r.date), hrvMs: r.hrvMs, restingHr: r.restingHr, sleepMinutes: r.sleepMinutes);

class SyncResult {
  const SyncResult({required this.days, required this.daysWithData, this.bodyMass});
  final int days;
  final int daysWithData;
  final BodyMassSample? bodyMass;
}

/// Stores per-day Health metrics and the readiness computed from them.
class ReadinessRepository {
  ReadinessRepository(this._db);
  final AppDatabase _db;

  static const _calc = ReadinessCalculator();
  static const _agg = DailyMetricsAggregator();

  Stream<List<DailyMetric>> watchDays() =>
      (_db.select(_db.dailyMetrics)..orderBy([(t) => OrderingTerm.asc(t.date)])).watch();

  Future<List<DailyMetric>> allDays() =>
      (_db.select(_db.dailyMetrics)..orderBy([(t) => OrderingTerm.asc(t.date)])).get();

  /// Readiness for [day] from stored metrics (today's row may not exist yet → all missing).
  ReadinessResult computeFor(DateTime day, List<DailyMetric> rows) {
    final key = dayKey(day);
    final metrics = rows.map(dayMetricsFromRow).toList();
    final today = metrics.where((m) => dayKey(m.date) == key).firstOrNull ?? DayMetrics(date: dateOnly(day));
    return _calc.compute(today, metrics);
  }

  /// Pulls [days] days of samples from Health, aggregates them per day and recomputes readiness.
  Future<SyncResult> sync(HealthDataSource source, {required DateTime now, int days = 45}) async {
    final today = dateOnly(now);
    final from = DateTime(today.year, today.month, today.day - days - 1, 12);
    final to = now;
    final results = await Future.wait([
      source.hrvSdnn(from, to),
      source.restingHeartRate(from, to),
      source.activeEnergy(from, to),
    ]);
    final sleep = await source.asleepIntervals(from, to);
    final hrv = results[0], rhr = results[1], energy = results[2];

    final energyByDay = <String, double>{};
    for (final e in energy) {
      final k = dayKey(e.to);
      energyByDay[k] = (energyByDay[k] ?? 0) + e.value;
    }

    var withData = 0;
    final rows = <DailyMetricsCompanion>[];
    for (var i = days; i >= 0; i--) {
      final day = addDays(today, -i);
      final m = _agg.aggregate(day: day, hrv: hrv, restingHr: rhr, asleep: sleep);
      if (m.hasAny) withData++;
      rows.add(DailyMetricsCompanion.insert(
        date: dayKey(day),
        hrvMs: Value(m.hrvMs),
        restingHr: Value(m.restingHr),
        sleepMinutes: Value(m.sleepMinutes),
        activeEnergyKcal: Value(energyByDay[dayKey(day)]),
        updatedAt: now,
      ));
    }
    await _db.batch((b) {
      for (final r in rows) {
        b.insert(_db.dailyMetrics, r, onConflict: DoUpdate((_) => r));
      }
    });
    await recomputeScores(sinceDays: days, now: now);

    BodyMassSample? mass;
    try {
      mass = await source.latestBodyMass();
    } catch (e) {
      debugPrint('Body mass read failed: $e');
    }
    if (mass != null) await _storeBodyMass(mass);
    return SyncResult(days: days + 1, daysWithData: withData, bodyMass: mass);
  }

  Future<void> _storeBodyMass(BodyMassSample s) async {
    final existing = await (_db.select(_db.bodyWeights)
          ..where((t) => t.source.equals('health') & t.measuredAt.equals(s.at)))
        .get();
    if (existing.isNotEmpty) return;
    await _db.into(_db.bodyWeights).insert(BodyWeightsCompanion.insert(measuredAt: s.at, kg: s.kg, source: 'health'));
  }

  /// Writes score/band/explanation for every stored day in the window.
  Future<void> recomputeScores({required int sinceDays, required DateTime now}) async {
    final rows = await allDays();
    final start = addDays(dateOnly(now), -sinceDays);
    await _db.batch((b) {
      for (final r in rows) {
        final day = parseDayKey(r.date);
        if (day.isBefore(start)) continue;
        final res = computeFor(day, rows);
        b.update(
          _db.dailyMetrics,
          DailyMetricsCompanion(
            readinessScore: Value(res.score),
            readinessBand: Value(res.calibrating ? null : res.band.name),
            calibrating: Value(res.calibrating),
            explanation: Value(res.reason),
          ),
          where: (t) => t.date.equals(r.date),
        );
      }
    });
  }

  /// Days whose readiness band was Red (for smart rest).
  Future<Set<DateTime>> redDays() async {
    final rows = await (_db.select(_db.dailyMetrics)..where((t) => t.readinessBand.equals(ReadinessBand.red.name))).get();
    return {for (final r in rows) parseDayKey(r.date)};
  }
}

class BodyWeightRepository {
  BodyWeightRepository(this._db);
  final AppDatabase _db;

  Stream<BodyWeight?> watchLatest() => (_db.select(_db.bodyWeights)
        ..orderBy([(t) => OrderingTerm.desc(t.measuredAt), (t) => OrderingTerm.desc(t.id)])
        ..limit(1))
      .watchSingleOrNull();

  Future<BodyWeight?> latest() => (_db.select(_db.bodyWeights)
        ..orderBy([(t) => OrderingTerm.desc(t.measuredAt), (t) => OrderingTerm.desc(t.id)])
        ..limit(1))
      .getSingleOrNull();

  Future<void> addManual(double kg, {DateTime? at}) => _db
      .into(_db.bodyWeights)
      .insert(BodyWeightsCompanion.insert(measuredAt: at ?? DateTime.now(), kg: kg, source: 'manual'));

  Future<List<BodyWeight>> all() => (_db.select(_db.bodyWeights)..orderBy([(t) => OrderingTerm.asc(t.measuredAt)])).get();
}
