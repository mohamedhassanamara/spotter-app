import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/training.dart';
import '../../../core/settings/app_settings.dart';
import '../../library/domain/exercise_info.dart';
import '../../program/data/program_repository.dart';
import '../../program/domain/program.dart';

class RoutineWithExercises {
  const RoutineWithExercises(this.routine, this.exercises);
  final Routine routine;
  final List<RoutineExercise> exercises;
}

class RoutineRepository {
  RoutineRepository(this._db);
  final AppDatabase _db;

  /// Routines with their exercises; re-emits when either table changes.
  Stream<List<RoutineWithExercises>> watchRoutines() {
    final q = _db.select(_db.routines).join([
      leftOuterJoin(_db.routineExercises, _db.routineExercises.routineId.equalsExp(_db.routines.id)),
    ])
      ..orderBy([
        OrderingTerm.asc(_db.routines.position),
        OrderingTerm.asc(_db.routines.id),
        OrderingTerm.asc(_db.routineExercises.position),
      ]);
    return q.watch().map((rows) {
      final byId = <int, RoutineWithExercises>{};
      for (final row in rows) {
        final r = row.readTable(_db.routines);
        final entry = byId.putIfAbsent(r.id, () => RoutineWithExercises(r, []));
        final e = row.readTableOrNull(_db.routineExercises);
        if (e != null) entry.exercises.add(e);
      }
      return byId.values.toList();
    });
  }

  Stream<RoutineWithExercises?> watchRoutine(int id) =>
      watchRoutines().map((all) => all.where((r) => r.routine.id == id).firstOrNull);

  Future<int> create(String name, {DateTime? now}) async {
    final count = await _db.routines.count().getSingle();
    return _db.into(_db.routines).insert(RoutinesCompanion.insert(
          name: name.trim().isEmpty ? 'New routine' : name.trim(),
          position: Value(count),
          createdAt: now ?? DateTime.now(),
        ));
  }

  Future<void> rename(int id, String name) =>
      (_db.update(_db.routines)..where((t) => t.id.equals(id))).write(RoutinesCompanion(name: Value(name.trim())));

  Future<void> delete(int id) => _db.transaction(() async {
        await (_db.delete(_db.routineExercises)..where((t) => t.routineId.equals(id))).go();
        await (_db.delete(_db.routines)..where((t) => t.id.equals(id))).go();
      });

  Future<int> addExercise(int routineId, ExerciseInfo exercise, SettingsModel settings) async {
    final existing = await (_db.select(_db.routineExercises)..where((t) => t.routineId.equals(routineId))).get();
    final range = exercise.defaultRange(compound: settings.compoundRange, isolation: settings.isolationRange);
    return _db.into(_db.routineExercises).insert(RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: exercise.id,
          position: existing.length,
          repMin: range.min,
          repMax: range.max,
          targetSets: 3,
          restSeconds: exercise.isCompound ? settings.defaultRestCompound : settings.defaultRestIsolation,
          targetRir: Value(settings.defaultRir),
        ));
  }

  Future<void> updateExercise(int id, {RepRange? range, int? targetSets, int? restSeconds, int? targetRir}) =>
      (_db.update(_db.routineExercises)..where((t) => t.id.equals(id))).write(RoutineExercisesCompanion(
        repMin: range == null ? const Value.absent() : Value(range.min),
        repMax: range == null ? const Value.absent() : Value(range.max),
        targetSets: targetSets == null ? const Value.absent() : Value(targetSets),
        restSeconds: restSeconds == null ? const Value.absent() : Value(restSeconds),
        targetRir: targetRir == null ? const Value.absent() : Value(targetRir),
      ));

  /// Program rows: a personal rep range, set count or rest on top of the program's prescription.
  Future<void> setProgramOverrides(int id, {RepRange? range, int? targetSets, int? restSeconds}) =>
      (_db.update(_db.routineExercises)..where((t) => t.id.equals(id))).write(RoutineExercisesCompanion(
        overrideRepMin: range == null ? const Value.absent() : Value(range.min),
        overrideRepMax: range == null ? const Value.absent() : Value(range.max),
        targetSets: targetSets == null ? const Value.absent() : Value(targetSets),
        restSeconds: restSeconds == null ? const Value.absent() : Value(restSeconds),
      ));

  /// "Reset to program": working sets from the program slots, the slot's rest, no rep-range override.
  Future<void> resetToProgram(RoutineExercise row, Program program) {
    final slots = [for (final id in decodeSlots(row.programSlots)) ?program.slot(id)];
    if (slots.isEmpty) return Future.value();
    return (_db.update(_db.routineExercises)..where((t) => t.id.equals(row.id))).write(RoutineExercisesCompanion(
      targetSets: Value(slots.fold(0, (n, s) => n + s.workingSets)),
      restSeconds: Value(slots.first.rest?.maxSeconds ?? 0),
      repMin: Value(slots.first.repRange.min),
      repMax: Value(slots.first.repRange.max),
      overrideRepMin: const Value(null),
      overrideRepMax: const Value(null),
    ));
  }

  Future<void> removeExercise(int id) => (_db.delete(_db.routineExercises)..where((t) => t.id.equals(id))).go();

  /// Persists a new order given the routine exercise ids in display order.
  Future<void> reorder(List<int> orderedIds) => _db.transaction(() async {
        for (var i = 0; i < orderedIds.length; i++) {
          await (_db.update(_db.routineExercises)..where((t) => t.id.equals(orderedIds[i])))
              .write(RoutineExercisesCompanion(position: Value(i)));
        }
      });

  Future<void> reorderRoutines(List<int> orderedIds) => _db.transaction(() async {
        for (var i = 0; i < orderedIds.length; i++) {
          await (_db.update(_db.routines)..where((t) => t.id.equals(orderedIds[i]))).write(RoutinesCompanion(position: Value(i)));
        }
      });
}
