import 'dart:math' as math;

import '../../features/readiness/domain/metrics_aggregator.dart';
import '../domain/dates.dart';
import 'health_data_source.dart';

/// Deterministic fake Health data for tests, the debug toggle and the seed generator.
///
/// Every night is derived from a hash of its date, so the same day always yields the same
/// samples. Includes a few rough nights (low HRV, short sleep, elevated RHR).
class FakeHealthDataSource implements HealthDataSource {
  FakeHealthDataSource({this.baseBodyMass = 80, this.workouts});

  final double baseBodyMass;

  /// Workouts "written" to Health, for tests.
  final List<(DateTime, DateTime)>? workouts;

  @override
  String get name => 'Fake data (debug)';

  @override
  bool get isFake => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  static math.Random _rng(DateTime day, int salt) {
    final d = dateOnly(day);
    return math.Random(d.year * 10000 + d.month * 100 + d.day + salt * 7919);
  }

  /// Night quality for the night before [day]: 0 = normal, 1 = rough, 2 = bad.
  static int _nightType(DateTime day) {
    final r = _rng(day, 1).nextDouble();
    if (r < 0.06) return 2;
    if (r < 0.2) return 1;
    return 0;
  }

  static double _gauss(math.Random r) {
    final u1 = r.nextDouble().clamp(1e-9, 1.0), u2 = r.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  Iterable<DateTime> _days(DateTime from, DateTime to) sync* {
    // A night belongs to the morning after it; include the day after `to` for overlap.
    for (var d = addDays(dateOnly(from), -1); !d.isAfter(addDays(dateOnly(to), 1)); d = addDays(d, 1)) {
      yield d;
    }
  }

  (DateTime, DateTime) _sleepFor(DateTime day) {
    final r = _rng(day, 2);
    final type = _nightType(day);
    final bedtime = DateTime(day.year, day.month, day.day - 1, 23, 0).add(Duration(minutes: (_gauss(r) * 25).round()));
    var minutes = 445 + _gauss(r) * 30;
    if (type == 1) minutes -= 70;
    if (type == 2) minutes -= 150;
    return (bedtime, bedtime.add(Duration(minutes: minutes.round().clamp(200, 600))));
  }

  bool _inRange(DateTime t, DateTime from, DateTime to) => !t.isBefore(from) && t.isBefore(to);

  @override
  Future<List<TimeInterval>> asleepIntervals(DateTime from, DateTime to) async {
    final out = <TimeInterval>[];
    for (final d in _days(from, to)) {
      final (start, end) = _sleepFor(d);
      // Split into two stages with a short awake gap, like a real watch recording.
      final mid = start.add(Duration(minutes: end.difference(start).inMinutes ~/ 2));
      final parts = [TimeInterval(start, mid), TimeInterval(mid.add(const Duration(minutes: 6)), end)];
      for (final p in parts) {
        if (p.end.isAfter(from) && p.start.isBefore(to)) out.add(p);
      }
    }
    return out;
  }

  @override
  Future<List<TimedValue>> hrvSdnn(DateTime from, DateTime to) async {
    final out = <TimedValue>[];
    for (final d in _days(from, to)) {
      final r = _rng(d, 3);
      final type = _nightType(d);
      final (start, end) = _sleepFor(d);
      var base = 58 + _gauss(r) * 6;
      if (type == 1) base -= 9;
      if (type == 2) base -= 18;
      for (var i = 1; i <= 3; i++) {
        final t = start.add(Duration(minutes: end.difference(start).inMinutes * i ~/ 4));
        if (_inRange(t, from, to)) out.add(TimedValue(t, t, (base + _gauss(r) * 4).clamp(15, 140)));
      }
    }
    return out;
  }

  @override
  Future<List<TimedValue>> restingHeartRate(DateTime from, DateTime to) async {
    final out = <TimedValue>[];
    for (final d in _days(from, to)) {
      final r = _rng(d, 4);
      final type = _nightType(d);
      var v = 55 + _gauss(r) * 1.8;
      if (type == 1) v += 3;
      if (type == 2) v += 6;
      final t = DateTime(d.year, d.month, d.day, 7, 30);
      if (_inRange(t, from, to)) out.add(TimedValue(t, t, v.roundToDouble()));
    }
    return out;
  }

  @override
  Future<List<TimedValue>> activeEnergy(DateTime from, DateTime to) async {
    final out = <TimedValue>[];
    for (final d in _days(from, to)) {
      final r = _rng(d, 5);
      final t = DateTime(d.year, d.month, d.day, 20);
      if (_inRange(t, from, to)) out.add(TimedValue(DateTime(d.year, d.month, d.day, 6), t, 450 + _gauss(r) * 120));
    }
    return out;
  }

  /// The fake source logs no food: nutrition is optional and the app must cope without it.
  @override
  Future<List<TimedValue>> dietaryEnergy(DateTime from, DateTime to) async => const [];

  @override
  Future<List<TimedValue>> dietaryProtein(DateTime from, DateTime to) async => const [];

  /// Body mass on [day]: a slow upward trend with day-to-day noise.
  double bodyMassOn(DateTime day) {
    final d = dateOnly(day);
    final r = _rng(d, 6);
    final weeks = d.difference(DateTime(2024, 1, 1)).inDays / 7;
    return double.parse((baseBodyMass + (weeks % 52) * 0.02 + _gauss(r) * 0.3).toStringAsFixed(1));
  }

  @override
  Future<BodyMassSample?> latestBodyMass() async {
    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day, 7);
    final day = at.isAfter(now) ? addDays(at, -1) : at;
    return BodyMassSample(day, bodyMassOn(day));
  }

  /// One weigh-in a week at 07:00.
  @override
  Future<List<BodyMassSample>> bodyMassHistory(DateTime from, DateTime to) async {
    final out = <BodyMassSample>[];
    for (var d = dateOnly(from); !d.isAfter(to); d = addDays(d, 7)) {
      final at = DateTime(d.year, d.month, d.day, 7);
      if (_inRange(at, from, to)) out.add(BodyMassSample(at, bodyMassOn(d)));
    }
    return out;
  }

  @override
  Future<bool> writeStrengthWorkout({required DateTime start, required DateTime end, String? title}) async {
    workouts?.add((start, end));
    return true;
  }
}
