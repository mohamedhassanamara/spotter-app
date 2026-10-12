import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/equipment.dart';
import '../../../core/domain/history.dart';
import '../../../core/domain/muscle_group.dart';
import '../../../core/domain/training.dart';
import '../../library/domain/exercise_info.dart';

LoggedSet loggedSetFromRow(WorkoutSet s) => LoggedSet(
      weight: s.weight,
      reps: s.reps,
      rpe: s.rpe,
      isWarmup: s.isWarmup,
      isOverride: s.isOverride,
      suggestedWeight: s.suggestedWeight,
      completed: s.completed,
    );

/// Loads finished sessions into the pure [TrainingHistory] model.
class HistoryRepository {
  HistoryRepository(this._db);
  final AppDatabase _db;

  /// Emits whenever sessions change (finish, delete); set edits inside the active session don't
  /// touch the sessions table, so the history isn't rebuilt on every rep.
  Stream<void> watchFinishedChanges() =>
      _db.tableUpdates(TableUpdateQuery.onTable(_db.sessions)).map((_) {}).asBroadcastStream();

  Future<TrainingHistory> load(Map<String, ExerciseInfo> catalog, {int? excludeSessionId}) async {
    final sessions = await (_db.select(_db.sessions)
          ..where((t) => t.status.equals('finished'))
          ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
        .get();
    if (sessions.isEmpty) return TrainingHistory.empty;
    final ids = sessions.map((s) => s.id).where((id) => id != excludeSessionId).toList();
    return TrainingHistory(await _build(sessions.where((s) => ids.contains(s.id)).toList(), catalog));
  }

  Future<HistSession?> loadSession(int id, Map<String, ExerciseInfo> catalog) async {
    final s = await (_db.select(_db.sessions)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (s == null) return null;
    return (await _build([s], catalog)).single;
  }

  Future<List<HistSession>> _build(List<Session> sessions, Map<String, ExerciseInfo> catalog) async {
    if (sessions.isEmpty) return const [];
    final ids = sessions.map((s) => s.id).toList();
    final exRows = await (_db.select(_db.sessionExercises)
          ..where((t) => t.sessionId.isIn(ids))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final exIds = exRows.map((e) => e.id).toList();
    final setRows = exIds.isEmpty
        ? <WorkoutSet>[]
        : await (_db.select(_db.workoutSets)
              ..where((t) => t.sessionExerciseId.isIn(exIds))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    final setsByEx = <int, List<WorkoutSet>>{};
    for (final s in setRows) {
      (setsByEx[s.sessionExerciseId] ??= []).add(s);
    }
    final exBySession = <int, List<SessionExercise>>{};
    for (final e in exRows) {
      (exBySession[e.sessionId] ??= []).add(e);
    }
    return [
      for (final s in sessions)
        HistSession(
          id: s.id,
          name: s.name,
          routineId: s.routineId,
          startedAt: s.startedAt,
          endedAt: s.endedAt,
          notes: s.notes,
          readinessScore: s.readinessScore,
          readinessBand: s.readinessBand,
          xpEarned: s.xpEarned,
          exercises: [
            for (final e in exBySession[s.id] ?? const <SessionExercise>[])
              HistExercise(
                id: e.id,
                exerciseId: e.exerciseId,
                name: e.displayName ?? catalog[e.exerciseId]?.name ?? e.exerciseId,
                targets: catalog[e.exerciseId]?.targets ?? MuscleTargets.empty,
                equipment: catalog[e.exerciseId]?.equipmentKind ?? EquipmentKind.other,
                range: RepRange(e.repMin, e.repMax),
                targetSets: e.targetSets,
                suggestionKind: SuggestionKind.fromName(e.suggestionKind),
                techniqueDay: _isTechniqueDay(e),
                suggestedWeight: e.suggestedWeight,
                suggestedReps: e.suggestedReps,
                notes: e.notes,
                sets: [
                  for (final w in setsByEx[e.id] ?? const <WorkoutSet>[])
                    HistSet(
                      id: w.id,
                      set: loggedSetFromRow(w),
                      completedAt: w.completedAt,
                      overrideReason: w.overrideReason,
                      targetRange: w.targetRepMin == null || w.targetRepMax == null ? null : RepRange(w.targetRepMin!, w.targetRepMax!),
                    ),
                ],
              ),
          ],
        ),
    ];
  }

  static bool _isTechniqueDay(SessionExercise e) {
    final raw = e.suggestionJson;
    if (raw == null) return false;
    return (jsonDecode(raw) as Map<String, dynamic>)['technique'] == true;
  }

  Future<void> deleteSession(int id) => _db.transaction(() async {
        final exIds = (await (_db.select(_db.sessionExercises)..where((t) => t.sessionId.equals(id))).get()).map((e) => e.id);
        await (_db.delete(_db.workoutSets)..where((t) => t.sessionExerciseId.isIn(exIds))).go();
        await (_db.delete(_db.sessionExercises)..where((t) => t.sessionId.equals(id))).go();
        await (_db.delete(_db.xpEvents)..where((t) => t.sessionId.equals(id))).go();
        await (_db.delete(_db.sessions)..where((t) => t.id.equals(id))).go();
      });
}
