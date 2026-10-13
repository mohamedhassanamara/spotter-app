import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/training.dart';
import '../../library/domain/exercise_info.dart';
import '../../program/data/program_repository.dart';
import '../../program/domain/program.dart';
import 'session_repository.dart';

/// How a finished-to-be session differs from the routine it started from.
class RoutineDiff {
  const RoutineDiff({this.added = const [], this.removed = const [], this.replaced = const [], this.reordered = false, this.setCounts = const [], this.targets = const []});

  /// Exercise names added mid-workout.
  final List<String> added;

  /// Routine rows no longer in the session.
  final List<String> removed;

  /// "Old → New".
  final List<String> replaced;
  final bool reordered;

  /// "Chest Press: 3 → 4 sets".
  final List<String> setCounts;

  /// "Chest Press: 8–10 reps".
  final List<String> targets;

  bool get isEmpty => added.isEmpty && removed.isEmpty && replaced.isEmpty && !reordered && setCounts.isEmpty && targets.isEmpty;

  List<String> get lines => [
        for (final a in added) 'Added $a',
        for (final r in removed) 'Removed $r',
        for (final r in replaced) 'Replaced $r',
        if (reordered) 'New exercise order',
        ...setCounts,
        ...targets,
      ];
}

Future<List<RoutineExercise>> routineRows(AppDatabase db, int routineId) => (db.select(db.routineExercises)
      ..where((t) => t.routineId.equals(routineId))
      ..orderBy([(t) => OrderingTerm.asc(t.position)]))
    .get();

Future<bool> routineExists(AppDatabase db, int routineId) async =>
    await (db.select(db.routines)..where((t) => t.id.equals(routineId))).getSingleOrNull() != null;

/// Working sets, counting any that readiness took away today (those aren't a routine change).
int _workingSets(ActiveExercise e) => e.sets.where((s) => !s.isWarmup && s.setType == null).length + (e.suggestion?.setsTrimmed ?? 0);

/// Compares the session with its routine: exercises added, removed, replaced, reordered; working-set
/// counts; target reps edited mid-workout.
RoutineDiff diffSessionAgainstRoutine({
  required List<ActiveExercise> session,
  required List<RoutineExercise> routine,
  required Map<String, ExerciseInfo> catalog,
}) {
  String nameOf(String id, String? display) => display ?? catalog[id]?.name ?? id;
  final byId = {for (final r in routine) r.id: r};
  final added = <String>[], replaced = <String>[], setCounts = <String>[], targets = <String>[];
  final seen = <int>[];
  for (final e in session) {
    final link = e.row.routineExerciseId;
    final r = link == null ? null : byId[link];
    final name = nameOf(e.row.exerciseId, e.row.displayName);
    if (r == null) {
      added.add(name);
      continue;
    }
    seen.add(r.id);
    if (r.exerciseId != e.row.exerciseId) replaced.add('${nameOf(r.exerciseId, r.displayName)} → $name');
    final n = _workingSets(e);
    if (n != r.targetSets) setCounts.add('$name: ${r.targetSets} → $n sets');
    if (e.row.targetsEdited) targets.add('$name: ${e.row.repMin}–${e.row.repMax} reps');
  }
  final removed = [for (final r in routine) if (!seen.contains(r.id)) nameOf(r.exerciseId, r.displayName)];
  final inRoutineOrder = [for (final r in routine) if (seen.contains(r.id)) r.id];
  return RoutineDiff(
    added: added,
    removed: removed,
    replaced: replaced,
    reordered: inRoutineOrder.join(',') != seen.join(','),
    setCounts: setCounts,
    targets: targets,
  );
}

/// "Update routine": the routine becomes what was done today. Removed rows are deleted, added and
/// replaced exercises get rows (a replacement keeps the program slots; it's a "substitution" when the
/// program lists it, else a "swap"), order follows the session, set counts become the working sets
/// done, and edited targets become the routine's rep-range override.
Future<void> updateRoutineFromSession({
  required AppDatabase db,
  required int routineId,
  required List<ActiveExercise> session,
  required Map<String, ExerciseInfo> catalog,
  Program? program,
}) =>
    db.transaction(() async {
      final rows = await (db.select(db.routineExercises)..where((t) => t.routineId.equals(routineId))).get();
      final byId = {for (final r in rows) r.id: r};
      final keep = <int>{};
      for (var i = 0; i < session.length; i++) {
        final e = session[i];
        final r = e.row.routineExerciseId == null ? null : byId[e.row.routineExerciseId];
        final sets = _workingSets(e).clamp(1, 20);
        final override = e.row.targetsEdited ? RepRange(e.row.repMin, e.row.repMax) : null;
        if (r != null) {
          keep.add(r.id);
          final replacedWith = r.exerciseId != e.row.exerciseId;
          String? relation = r.programRelation;
          if (replacedWith && r.programSlots != null && program != null) {
            final slot = program.slot(decodeSlots(r.programSlots).first);
            final name = (catalog[e.row.exerciseId]?.name ?? '').toLowerCase();
            relation = slot != null && slot.substitutions.any((x) => x.toLowerCase() == name) ? 'substitution' : 'swap';
          }
          await (db.update(db.routineExercises)..where((t) => t.id.equals(r.id))).write(RoutineExercisesCompanion(
            exerciseId: Value(e.row.exerciseId),
            position: Value(i),
            targetSets: Value(sets),
            displayName: replacedWith ? Value(e.row.displayName ?? catalog[e.row.exerciseId]?.name) : const Value.absent(),
            programRelation: Value(relation),
            overrideRepMin: override == null ? const Value.absent() : Value(override.min),
            overrideRepMax: override == null ? const Value.absent() : Value(override.max),
            repMin: override == null ? const Value.absent() : Value(override.min),
            repMax: override == null ? const Value.absent() : Value(override.max),
            supersetGroup: Value(e.row.supersetGroup),
          ));
        } else {
          final id = await db.into(db.routineExercises).insert(RoutineExercisesCompanion.insert(
                routineId: routineId,
                exerciseId: e.row.exerciseId,
                position: i,
                repMin: e.row.repMin,
                repMax: e.row.repMax,
                targetSets: sets,
                restSeconds: e.row.restSeconds,
                targetRir: Value(e.row.targetRir),
                programSlots: Value(e.row.programSlots),
                programRelation: Value(e.row.programSlots == null ? null : 'extra'),
                displayName: Value(e.row.displayName),
                supersetGroup: Value(e.row.supersetGroup),
              ));
          keep.add(id);
          await (db.update(db.sessionExercises)..where((t) => t.id.equals(e.row.id)))
              .write(SessionExercisesCompanion(routineExerciseId: Value(id)));
        }
      }
      await (db.delete(db.routineExercises)..where((t) => t.routineId.equals(routineId) & t.id.isNotIn(keep))).go();
    });
