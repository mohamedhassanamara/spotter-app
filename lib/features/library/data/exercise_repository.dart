import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/db/database.dart';
import '../domain/exercise_info.dart';

/// Bump when assets/exercises.json is refreshed so existing installs re-import it.
const int exerciseDatasetVersion = 3; // v2: + assets/extra_exercises.json; v3: + Assisted Dip (Machine)

class ExerciseRepository {
  ExerciseRepository(this._db);
  final AppDatabase _db;

  static const _datasetKey = 'exercise_dataset_version';

  /// Imports the bundled free-exercise-db catalogue on first launch (or after a dataset bump).
  /// Favorites and custom exercises are preserved.
  Future<void> ensureSeeded({String? jsonOverride, String? extraJsonOverride}) async {
    final current = int.tryParse(await _db.getSetting(_datasetKey) ?? '');
    if (current == exerciseDatasetVersion) return;
    final raw = jsonOverride ?? await rootBundle.loadString('assets/exercises.json');
    final extraRaw = extraJsonOverride ?? await rootBundle.loadString('assets/extra_exercises.json');
    final list = [
      ...(jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>(),
      // Built-in additions (Pendulum Squat, machine Assisted Pull-Up…), same shape, ids start with sp_.
      ...((jsonDecode(extraRaw) as Map<String, dynamic>)['exercises'] as List<dynamic>).cast<Map<String, dynamic>>(),
    ];
    await _db.batch((b) {
      for (final e in list) {
        final companion = ExercisesCompanion.insert(
          id: e['id'] as String,
          name: e['name'] as String,
          primaryMuscles: Value(jsonEncode(e['primaryMuscles'] ?? const [])),
          secondaryMuscles: Value(jsonEncode(e['secondaryMuscles'] ?? const [])),
          equipment: Value(e['equipment'] as String?),
          level: Value(e['level'] as String?),
          mechanic: Value(e['mechanic'] as String?),
          category: Value(e['category'] as String?),
          instructions: Value(jsonEncode(e['instructions'] ?? const [])),
          images: Value(jsonEncode(e['images'] ?? const [])),
        );
        b.insert(
          _db.exercises,
          companion,
          onConflict: DoUpdate((old) => companion.copyWith(isFavorite: const Value.absent())),
        );
      }
    });
    await _db.putSetting(_datasetKey, '$exerciseDatasetVersion');
  }

  static List<String> _list(String raw) => (jsonDecode(raw) as List<dynamic>).cast<String>();

  static ExerciseInfo toInfo(Exercise e) => ExerciseInfo(
        id: e.id,
        name: e.name,
        primaryMuscles: _list(e.primaryMuscles),
        secondaryMuscles: _list(e.secondaryMuscles),
        equipment: e.equipment,
        level: e.level,
        mechanic: e.mechanic,
        category: e.category,
        instructions: _list(e.instructions),
        images: _list(e.images),
        isCustom: e.isCustom,
        isFavorite: e.isFavorite,
        notes: e.notes,
      );

  /// The whole catalogue keyed by id; updates on favorite toggles and custom exercise edits.
  Stream<Map<String, ExerciseInfo>> watchCatalog() => (_db.select(_db.exercises)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch()
      .map((rows) => {for (final r in rows) r.id: toInfo(r)});

  Future<ExerciseInfo?> byId(String id) async {
    final row = await (_db.select(_db.exercises)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : toInfo(row);
  }

  Future<void> setFavorite(String id, bool favorite) =>
      (_db.update(_db.exercises)..where((t) => t.id.equals(id))).write(ExercisesCompanion(isFavorite: Value(favorite)));

  Future<String> createCustom({
    required String name,
    required List<String> primaryMuscles,
    required List<String> secondaryMuscles,
    required String? equipment,
    required bool compound,
    String? notes,
  }) async {
    final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    await _db.into(_db.exercises).insert(ExercisesCompanion.insert(
          id: id,
          name: name.trim(),
          primaryMuscles: Value(jsonEncode(primaryMuscles)),
          secondaryMuscles: Value(jsonEncode(secondaryMuscles)),
          equipment: Value(equipment),
          mechanic: Value(compound ? 'compound' : 'isolation'),
          category: const Value('strength'),
          isCustom: const Value(true),
          notes: Value(notes?.trim().isEmpty ?? true ? null : notes!.trim()),
        ));
    return id;
  }

  Future<void> updateCustom(
    String id, {
    required String name,
    required List<String> primaryMuscles,
    required List<String> secondaryMuscles,
    required String? equipment,
    required bool compound,
    String? notes,
  }) =>
      (_db.update(_db.exercises)..where((t) => t.id.equals(id) & t.isCustom.equals(true))).write(ExercisesCompanion(
        name: Value(name.trim()),
        primaryMuscles: Value(jsonEncode(primaryMuscles)),
        secondaryMuscles: Value(jsonEncode(secondaryMuscles)),
        equipment: Value(equipment),
        mechanic: Value(compound ? 'compound' : 'isolation'),
        notes: Value(notes?.trim().isEmpty ?? true ? null : notes!.trim()),
      ));

  /// Custom exercises can only be deleted when they've never been used.
  Future<bool> deleteCustomIfUnused(String id) async {
    final usedInSessions = await (_db.select(_db.sessionExercises)..where((t) => t.exerciseId.equals(id))..limit(1)).get();
    final usedInRoutines = await (_db.select(_db.routineExercises)..where((t) => t.exerciseId.equals(id))..limit(1)).get();
    if (usedInSessions.isNotEmpty || usedInRoutines.isNotEmpty) return false;
    await (_db.delete(_db.exercises)..where((t) => t.id.equals(id) & t.isCustom.equals(true))).go();
    return true;
  }
}
