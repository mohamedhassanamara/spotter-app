import 'dart:convert';

import '../../../core/db/database.dart';
import '../../../core/domain/gym.dart';
import '../domain/suggestion_engine.dart';

/// Settings → My gym equipment, per-exercise stack overrides, and form resets.
class GymRepository {
  GymRepository(this._db);
  final AppDatabase _db;

  static const formResetsKey = 'form_resets';

  Stream<GymEquipment> watch() => _db.watchSettings().map((m) => GymEquipment.decode(m[GymEquipment.key]));

  Future<GymEquipment> load() async => GymEquipment.decode(await _db.getSetting(GymEquipment.key));

  Future<void> save(GymEquipment g) => _db.putSetting(GymEquipment.key, g.encode());

  /// Exercise menu → Weight steps. Null clears the override (back to the gym default).
  Future<void> setStack(String exerciseId, StackSpec? spec) async {
    final g = await load();
    final per = {...g.perExercise};
    spec == null ? per.remove(exerciseId) : per[exerciseId] = spec;
    await save(g.copyWith(perExercise: per));
  }

  static Map<String, FormReset> decodeResets(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    return {
      for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
        e.key: FormReset(
          weight: ((e.value as Map<String, dynamic>)['weight'] as num).toDouble(),
          at: DateTime.parse((e.value as Map<String, dynamic>)['at'] as String),
        ),
    };
  }

  Stream<Map<String, FormReset>> watchResets() => _db.watchSettings().map((m) => decodeResets(m[formResetsKey]));

  Future<Map<String, FormReset>> resets() async => decodeResets(await _db.getSetting(formResetsKey));

  /// Exercise menu → Form reset: progression restarts from [weight] as of [at] (the day of the
  /// lighter session; earlier, heavier sessions stop counting).
  Future<void> setFormReset(String exerciseId, {required double weight, required DateTime at}) async {
    final all = {...await resets(), exerciseId: FormReset(weight: weight, at: at)};
    await _db.putSetting(formResetsKey, jsonEncode({
      for (final e in all.entries) e.key: {'weight': e.value.weight, 'at': e.value.at.toIso8601String()},
    }));
  }
}
