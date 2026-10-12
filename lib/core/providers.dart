import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';
import 'domain/equipment.dart';
import 'domain/training.dart';
import 'settings/app_settings.dart';

/// The single database instance; overridden in `main()` (and in tests with an in-memory DB).
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider must be overridden'));

/// Wall clock, overridable in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final settingsProvider = StreamProvider<SettingsModel>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchSettings().map(SettingsModel.fromMap);
});

/// Latest settings, falling back to defaults while the stream is loading.
final currentSettingsProvider = Provider<SettingsModel>((ref) {
  return ref.watch(settingsProvider).value ?? const SettingsModel();
});

final settingsControllerProvider = Provider<SettingsController>((ref) => SettingsController(ref.watch(databaseProvider)));

class SettingsController {
  SettingsController(this._db);
  final AppDatabase _db;

  Future<void> setOnboarded(bool v) => _db.putSetting(SettingsModel.kOnboarded, '$v');
  Future<void> setWeeklyGoal(int v) => _db.putSetting(SettingsModel.kWeeklyGoal, '${v.clamp(1, 14)}');
  Future<void> setIncrement(Increments current, EquipmentKind kind, double v) =>
      _db.putSetting(SettingsModel.kIncrements, SettingsModel.encodeIncrements(current.copyWith(kind, v)));
  Future<void> setCompoundRange(RepRange r) => _db.putSetting(SettingsModel.kCompoundRange, SettingsModel.encodeRange(r));
  Future<void> setIsolationRange(RepRange r) => _db.putSetting(SettingsModel.kIsolationRange, SettingsModel.encodeRange(r));
  Future<void> setDefaultRir(int v) => _db.putSetting(SettingsModel.kDefaultRir, '${v.clamp(0, 5)}');
  Future<void> setRestCompound(int s) => _db.putSetting(SettingsModel.kRestCompound, '$s');
  Future<void> setRestIsolation(int s) => _db.putSetting(SettingsModel.kRestIsolation, '$s');
  Future<void> setUseFakeHealth(bool v) => _db.putSetting(SettingsModel.kFakeHealth, '$v');
  Future<void> setHealthRequested(bool v) => _db.putSetting(SettingsModel.kHealthRequested, '$v');

  Future<void> setRestTimer(DateTime? endsAt, int? totalSeconds) async {
    if (endsAt == null) {
      await _db.deleteSetting(SettingsModel.kRestEndsAt);
      await _db.deleteSetting(SettingsModel.kRestTotal);
    } else {
      await _db.putSetting(SettingsModel.kRestEndsAt, endsAt.toIso8601String());
      await _db.putSetting(SettingsModel.kRestTotal, '${totalSeconds ?? 0}');
    }
  }
}
