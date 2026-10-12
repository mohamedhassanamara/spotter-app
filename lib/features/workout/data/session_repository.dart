import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/training.dart';
import '../../coach/data/coach_context.dart';
import '../../coach/domain/guardrail.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../library/domain/exercise_info.dart';
import '../../readiness/domain/readiness.dart';
import 'routine_repository.dart';

/// Suggestion as stored with a session exercise.
class StoredSuggestion {
  const StoredSuggestion({
    required this.kind,
    required this.weight,
    required this.reps,
    required this.sets,
    required this.headline,
    required this.why,
    required this.techniqueDay,
    required this.rampUp,
    required this.band,
  });

  final SuggestionKind kind;
  final double? weight;
  final int? reps;
  final int? sets;
  final String headline;
  final List<String> why;
  final bool techniqueDay;
  final bool rampUp;
  final ReadinessBand? band;

  static String encode(Suggestion s) => jsonEncode({
        'headline': s.headline,
        'why': s.why,
        'technique': s.techniqueDay,
        'ramp': s.rampUp,
        'band': s.band.name,
      });

  static StoredSuggestion? fromRow(SessionExercise e) {
    final raw = e.suggestionJson;
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return StoredSuggestion(
      kind: SuggestionKind.fromName(e.suggestionKind),
      weight: e.suggestedWeight,
      reps: e.suggestedReps,
      sets: e.suggestedSets,
      headline: j['headline'] as String,
      why: (j['why'] as List<dynamic>).cast<String>(),
      techniqueDay: j['technique'] as bool? ?? false,
      rampUp: j['ramp'] as bool? ?? false,
      band: ReadinessBand.fromName(j['band'] as String?),
    );
  }
}

class ActiveExercise {
  const ActiveExercise({required this.row, required this.sets, required this.suggestion});
  final SessionExercise row;
  final List<WorkoutSet> sets;
  final StoredSuggestion? suggestion;

  RepRange get range => RepRange(row.repMin, row.repMax);
}

class ActiveSession {
  const ActiveSession({required this.session, required this.exercises});
  final Session session;
  final List<ActiveExercise> exercises;

  int get completedWorkingSets => exercises.expand((e) => e.sets).where((s) => s.completed && !s.isWarmup).length;
}

class SessionRepository {
  SessionRepository(this._db);
  final AppDatabase _db;

  static const _guardrail = Guardrail();

  /// The in-progress session with its exercises and sets; null when none.
  Stream<ActiveSession?> watchActive() {
    final q = _db.select(_db.sessions).join([
      leftOuterJoin(_db.sessionExercises, _db.sessionExercises.sessionId.equalsExp(_db.sessions.id)),
      leftOuterJoin(_db.workoutSets, _db.workoutSets.sessionExerciseId.equalsExp(_db.sessionExercises.id)),
    ])
      ..where(_db.sessions.status.equals('active'))
      ..orderBy([
        OrderingTerm.desc(_db.sessions.startedAt),
        OrderingTerm.asc(_db.sessionExercises.position),
        OrderingTerm.asc(_db.workoutSets.position),
      ]);
    return q.watch().map((rows) {
      if (rows.isEmpty) return null;
      final session = rows.first.readTable(_db.sessions);
      final exercises = <int, SessionExercise>{};
      final sets = <int, List<WorkoutSet>>{};
      for (final r in rows) {
        if (r.readTable(_db.sessions).id != session.id) continue;
        final e = r.readTableOrNull(_db.sessionExercises);
        if (e == null) continue;
        exercises[e.id] = e;
        final s = r.readTableOrNull(_db.workoutSets);
        if (s != null) (sets[e.id] ??= []).add(s);
      }
      final ordered = exercises.values.toList()..sort((a, b) => a.position.compareTo(b.position));
      return ActiveSession(
        session: session,
        exercises: [
          for (final e in ordered)
            ActiveExercise(row: e, sets: sets[e.id] ?? const [], suggestion: StoredSuggestion.fromRow(e)),
        ],
      );
    });
  }

  Future<Session?> activeSession() =>
      (_db.select(_db.sessions)..where((t) => t.status.equals('active'))..limit(1)).getSingleOrNull();

  /// Starts a session, from a routine or empty, computing a suggestion for each exercise.
  Future<int> start({
    required String name,
    required CoachContext coach,
    required Map<String, ExerciseInfo> catalog,
    RoutineWithExercises? routine,
  }) {
    return _db.transaction(() async {
      final r = coach.readiness;
      final id = await _db.into(_db.sessions).insert(SessionsCompanion.insert(
            name: name,
            routineId: Value(routine?.routine.id),
            startedAt: coach.now,
            readinessScore: Value(r == null || r.calibrating ? null : r.score),
            readinessBand: Value(r == null || r.calibrating ? null : r.band.name),
          ));
      if (routine != null) {
        var pos = 0;
        for (final re in routine.exercises) {
          final info = catalog[re.exerciseId];
          if (info == null) continue;
          await _insertExercise(
            sessionId: id,
            info: info,
            position: pos++,
            range: RepRange(re.repMin, re.repMax),
            targetSets: re.targetSets,
            restSeconds: re.restSeconds,
            targetRir: re.targetRir,
            coach: coach,
          );
        }
      }
      return id;
    });
  }

  Future<int> addExercise({
    required int sessionId,
    required ExerciseInfo info,
    required RepRange range,
    required int targetSets,
    required int restSeconds,
    required int targetRir,
    required CoachContext coach,
  }) async {
    final count = await (_db.select(_db.sessionExercises)..where((t) => t.sessionId.equals(sessionId))).get();
    final maxPos = count.fold<int>(-1, (m, e) => e.position > m ? e.position : m);
    return _insertExercise(
      sessionId: sessionId,
      info: info,
      position: maxPos + 1,
      range: range,
      targetSets: targetSets,
      restSeconds: restSeconds,
      targetRir: targetRir,
      coach: coach,
    );
  }

  Future<int> _insertExercise({
    required int sessionId,
    required ExerciseInfo info,
    required int position,
    required RepRange range,
    required int targetSets,
    required int restSeconds,
    required int targetRir,
    required CoachContext coach,
  }) async {
    final s = coach.suggest(info, range, targetSets, targetRir);
    final exId = await _db.into(_db.sessionExercises).insert(SessionExercisesCompanion.insert(
          sessionId: sessionId,
          exerciseId: info.id,
          position: position,
          repMin: range.min,
          repMax: range.max,
          targetSets: targetSets,
          restSeconds: restSeconds,
          targetRir: Value(targetRir),
          suggestionKind: Value(s.kind.name),
          suggestedWeight: Value(s.weight),
          suggestedReps: Value(s.reps),
          suggestedSets: Value(s.sets),
          suggestionJson: Value(StoredSuggestion.encode(s)),
        ));
    // Calibration sets ramp freely, so they carry no suggested weight (no override detection).
    final suggested = s.rampUp ? null : s.weight;
    for (var i = 0; i < s.sets; i++) {
      await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
            sessionExerciseId: exId,
            position: i,
            weight: Value(s.weight),
            reps: Value(s.reps),
            suggestedWeight: Value(suggested),
            suggestedReps: Value(s.reps),
          ));
    }
    return exId;
  }

  Future<void> removeExercise(int sessionExerciseId) => _db.transaction(() async {
        await (_db.delete(_db.workoutSets)..where((t) => t.sessionExerciseId.equals(sessionExerciseId))).go();
        await (_db.delete(_db.sessionExercises)..where((t) => t.id.equals(sessionExerciseId))).go();
      });

  Future<void> reorderExercises(List<int> orderedIds) => _db.transaction(() async {
        for (var i = 0; i < orderedIds.length; i++) {
          await (_db.update(_db.sessionExercises)..where((t) => t.id.equals(orderedIds[i])))
              .write(SessionExercisesCompanion(position: Value(i)));
        }
      });

  Future<void> setExerciseNotes(int sessionExerciseId, String notes) =>
      (_db.update(_db.sessionExercises)..where((t) => t.id.equals(sessionExerciseId)))
          .write(SessionExercisesCompanion(notes: Value(notes)));

  Future<void> setSessionNotes(int sessionId, String notes) =>
      (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId))).write(SessionsCompanion(notes: Value(notes)));

  Future<void> renameSession(int sessionId, String name) =>
      (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId))).write(SessionsCompanion(name: Value(name)));

  /// Adds a set, copying the last set's load. Warm-ups carry no suggestion.
  Future<void> addSet(ActiveExercise ex, {bool warmup = false}) async {
    final last = ex.sets.isEmpty ? null : ex.sets.last;
    final sug = ex.suggestion;
    final weight = warmup
        ? ((sug?.weight ?? last?.weight ?? 0) * 0.5)
        : (last?.weight ?? sug?.weight ?? 0);
    final position = warmup ? -1 - ex.sets.where((s) => s.isWarmup).length : (last?.position ?? -1) + 1;
    await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
          sessionExerciseId: ex.row.id,
          position: position,
          isWarmup: Value(warmup),
          weight: Value(warmup ? (weight / 2.5).round() * 2.5 : weight),
          reps: Value(warmup ? 5 : (last?.reps ?? sug?.reps ?? ex.row.repMin)),
          suggestedWeight: Value(warmup || (sug?.rampUp ?? false) ? null : sug?.weight),
          suggestedReps: Value(warmup ? null : sug?.reps),
        ));
    await _renumber(ex.row.id);
  }

  Future<void> _renumber(int sessionExerciseId) async {
    final sets = await (_db.select(_db.workoutSets)
          ..where((t) => t.sessionExerciseId.equals(sessionExerciseId))
          ..orderBy([(t) => OrderingTerm.asc(t.position), (t) => OrderingTerm.asc(t.id)]))
        .get();
    for (var i = 0; i < sets.length; i++) {
      if (sets[i].position != i) {
        await (_db.update(_db.workoutSets)..where((t) => t.id.equals(sets[i].id))).write(WorkoutSetsCompanion(position: Value(i)));
      }
    }
  }

  Future<void> deleteSet(WorkoutSet set) async {
    await (_db.delete(_db.workoutSets)..where((t) => t.id.equals(set.id))).go();
    await _renumber(set.sessionExerciseId);
  }

  Future<void> updateSet(int id, {double? weight, int? reps, double? Function()? rpe, bool? isWarmup}) =>
      (_db.update(_db.workoutSets)..where((t) => t.id.equals(id))).write(WorkoutSetsCompanion(
        weight: weight == null ? const Value.absent() : Value(weight),
        reps: reps == null ? const Value.absent() : Value(reps),
        rpe: rpe == null ? const Value.absent() : Value(rpe()),
        isWarmup: isWarmup == null ? const Value.absent() : Value(isWarmup),
      ));

  /// Would completing this set with [weight] count as an override?
  bool wouldOverride(WorkoutSet set, double weight, {bool? isWarmup}) =>
      _guardrail.isOverride(weight: weight, suggested: set.suggestedWeight, isWarmup: isWarmup ?? set.isWarmup);

  /// Marks a set done. Override sets must carry an RPE and a reason (enforced by the UI and here).
  Future<void> completeSet(
    WorkoutSet set, {
    required double weight,
    required int reps,
    required double? rpe,
    required bool isWarmup,
    OverrideReason? reason,
    required DateTime now,
  }) async {
    final override = wouldOverride(set, weight, isWarmup: isWarmup);
    if (override && (rpe == null || reason == null)) {
      throw StateError('Override sets need an RPE and a reason');
    }
    await (_db.update(_db.workoutSets)..where((t) => t.id.equals(set.id))).write(WorkoutSetsCompanion(
      weight: Value(weight),
      reps: Value(reps),
      rpe: Value(rpe),
      isWarmup: Value(isWarmup),
      completed: const Value(true),
      completedAt: Value(now),
      isOverride: Value(override),
      overrideReason: Value(override ? reason!.name : null),
    ));
  }

  Future<void> uncompleteSet(int id) => (_db.update(_db.workoutSets)..where((t) => t.id.equals(id))).write(
        const WorkoutSetsCompanion(
          completed: Value(false),
          completedAt: Value(null),
          isOverride: Value(false),
          overrideReason: Value(null),
        ),
      );

  Future<void> discard(int sessionId) => _db.transaction(() async {
        final exIds = (await (_db.select(_db.sessionExercises)..where((t) => t.sessionId.equals(sessionId))).get())
            .map((e) => e.id)
            .toList();
        await (_db.delete(_db.workoutSets)..where((t) => t.sessionExerciseId.isIn(exIds))).go();
        await (_db.delete(_db.sessionExercises)..where((t) => t.sessionId.equals(sessionId))).go();
        await (_db.delete(_db.sessions)..where((t) => t.id.equals(sessionId))).go();
      });
}
