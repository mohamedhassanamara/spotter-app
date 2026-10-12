import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../../features/readiness/domain/metrics_aggregator.dart';
import 'health_data_source.dart';

/// Real Apple Health implementation (iOS only).
class HealthKitDataSource implements HealthDataSource {
  HealthKitDataSource([Health? health]) : _health = health ?? Health();

  final Health _health;
  bool _configured = false;

  static const _asleepTypes = [
    HealthDataType.SLEEP_ASLEEP, // unspecified
    HealthDataType.SLEEP_LIGHT, // core
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  static const _readTypes = [
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.RESTING_HEART_RATE,
    ..._asleepTypes,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WEIGHT,
  ];

  @override
  String get name => 'Apple Health';

  @override
  bool get isFake => false;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> isAvailable() async => Platform.isIOS;

  @override
  Future<bool> requestPermissions() async {
    if (!Platform.isIOS) return false;
    try {
      await _configure();
      final types = [..._readTypes, HealthDataType.WORKOUT];
      final permissions = [
        for (final _ in _readTypes) HealthDataAccess.READ,
        HealthDataAccess.READ_WRITE,
      ];
      return await _health.requestAuthorization(types, permissions: permissions);
    } catch (e) {
      debugPrint('Health authorization failed: $e');
      return false;
    }
  }

  Future<List<HealthDataPoint>> _read(List<HealthDataType> types, DateTime from, DateTime to) async {
    if (!Platform.isIOS) return const [];
    try {
      await _configure();
      return await _health.getHealthDataFromTypes(types: types, startTime: from, endTime: to);
    } catch (e) {
      debugPrint('Health read ${types.map((t) => t.name).join(',')} failed: $e');
      return const [];
    }
  }

  static double? _num(HealthDataPoint p) {
    final v = p.value;
    return v is NumericHealthValue ? v.numericValue.toDouble() : null;
  }

  Future<List<TimedValue>> _numeric(HealthDataType type, DateTime from, DateTime to) async {
    final points = await _read([type], from, to);
    return [
      for (final p in points)
        if (_num(p) case final v?) TimedValue(p.dateFrom.toLocal(), p.dateTo.toLocal(), v),
    ];
  }

  @override
  Future<List<TimedValue>> hrvSdnn(DateTime from, DateTime to) =>
      _numeric(HealthDataType.HEART_RATE_VARIABILITY_SDNN, from, to);

  @override
  Future<List<TimedValue>> restingHeartRate(DateTime from, DateTime to) =>
      _numeric(HealthDataType.RESTING_HEART_RATE, from, to);

  @override
  Future<List<TimedValue>> activeEnergy(DateTime from, DateTime to) =>
      _numeric(HealthDataType.ACTIVE_ENERGY_BURNED, from, to);

  @override
  Future<List<TimeInterval>> asleepIntervals(DateTime from, DateTime to) async {
    final points = await _read(_asleepTypes, from, to);
    return [
      for (final p in points)
        if (p.dateTo.isAfter(p.dateFrom)) TimeInterval(p.dateFrom.toLocal(), p.dateTo.toLocal()),
    ];
  }

  @override
  Future<BodyMassSample?> latestBodyMass() async {
    final now = DateTime.now();
    final points = await _read([HealthDataType.WEIGHT], now.subtract(const Duration(days: 365)), now);
    BodyMassSample? latest;
    for (final p in points) {
      final v = _num(p);
      if (v == null || v <= 0) continue;
      if (latest == null || p.dateFrom.isAfter(latest.at)) latest = BodyMassSample(p.dateFrom.toLocal(), v);
    }
    return latest;
  }

  @override
  Future<bool> writeStrengthWorkout({required DateTime start, required DateTime end, String? title}) async {
    if (!Platform.isIOS) return false;
    try {
      await _configure();
      return await _health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
        start: start,
        end: end,
        title: title,
      );
    } catch (e) {
      debugPrint('Health workout write failed: $e');
      return false;
    }
  }
}
