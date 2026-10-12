import '../../features/readiness/domain/metrics_aggregator.dart';

/// Body mass sample.
class BodyMassSample {
  const BodyMassSample(this.at, this.kg);
  final DateTime at;
  final double kg;
}

enum HealthAccess { unknown, requested, unavailable }

/// Abstraction over Apple Health so the app (and tests) never touch HealthKit directly.
///
/// iOS never reveals whether *read* access was granted, so "missing" is inferred from
/// empty results and reported in the UI.
abstract interface class HealthDataSource {
  /// Short name for the UI ("Apple Health", "Fake data").
  String get name;

  bool get isFake;

  Future<bool> isAvailable();

  /// Shows the system permission sheet. Returns false if the request itself failed.
  Future<bool> requestPermissions();

  Future<List<TimedValue>> hrvSdnn(DateTime from, DateTime to);

  Future<List<TimedValue>> restingHeartRate(DateTime from, DateTime to);

  /// Asleep intervals only (core/deep/REM/unspecified); in-bed and awake are excluded.
  Future<List<TimeInterval>> asleepIntervals(DateTime from, DateTime to);

  /// Active energy samples in kcal.
  Future<List<TimedValue>> activeEnergy(DateTime from, DateTime to);

  Future<BodyMassSample?> latestBodyMass();

  /// Every body mass sample in the window, oldest first. Ranks score each set against the
  /// bodyweight on its day, so the history matters, not just the latest value.
  Future<List<BodyMassSample>> bodyMassHistory(DateTime from, DateTime to);

  /// Saves a Traditional Strength Training workout. Returns true on success.
  Future<bool> writeStrengthWorkout({required DateTime start, required DateTime end, String? title});
}
