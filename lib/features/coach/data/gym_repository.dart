import 'dart:convert';

import '../../../core/db/database.dart';
import '../../../core/domain/gym.dart';
import '../../../core/domain/load_types.dart';
import '../domain/suggestion_engine.dart';

/// Settings → My gym equipment, per-exercise stack overrides, and form resets.
class GymRepository {
  GymRepository(this._db);
  final AppDatabase _db;

  static const formResetsKey = 'form_resets';
  static const formResetOffersKey = 'form_reset_offered';

  /// Session exercises already offered a form reset (once per exercise per workout, even across an app
  /// restart mid-workout). Ids are never reused, so old ones are harmless; the list keeps the latest 300.
  Future<Set<int>> formResetOffered() async {
    final raw = await _db.getSetting(formResetOffersKey);
    return raw == null || raw.isEmpty ? <int>{} : {...(jsonDecode(raw) as List<dynamic>).cast<int>()};
  }

  Future<void> markFormResetOffered(int sessionExerciseId) async {
    final all = [...await formResetOffered(), sessionExerciseId];
    await _db.putSetting(formResetOffersKey, jsonEncode(all.length > 300 ? all.sublist(all.length - 300) : all));
  }

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

  /// Exercise menu → Weight steps: how this exercise is loaded. Null goes back to the classification.
  Future<void> setLoadType(String exerciseId, LoadType? type) async {
    final g = await load();
    final over = {...g.typeOverrides};
    type == null ? over.remove(exerciseId) : over[exerciseId] = type;
    await save(g.copyWith(typeOverrides: over));
  }

  static const platesMigratedKey = 'smallest_plate_2_5';

  /// Startup, once: the first version defaulted the smallest plate to 2.25 kg; this gym's is 2.5 kg.
  /// A stored 2.25 (the old default) becomes 2.5, and the plate stays editable afterwards.
  static Future<void> ensureSmallestPlate(AppDatabase db) async {
    if (await db.getSetting(platesMigratedKey) != null) return;
    final raw = await db.getSetting(GymEquipment.key);
    if (raw != null) {
      final g = GymEquipment.decode(raw);
      if ((g.smallestPlate - 2.25).abs() < 1e-9) await db.putSetting(GymEquipment.key, g.copyWith(smallestPlate: GymEquipment.defaultSmallestPlate).encode());
    }
    await db.putSetting(platesMigratedKey, '1');
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
