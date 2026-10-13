import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/training.dart';
import '../../coach/data/coach_context.dart';
import '../../coach/domain/guardrail.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../library/domain/exercise_info.dart';
import '../../readiness/domain/readiness.dart';
import '../../program/data/program_repository.dart';
import '../../program/domain/program.dart';
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
    Program? program,
    int programWeek = 2,
    int? warmupOverride,
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
            program: program,
            programSlots: decodeSlots(re.programSlots),
            programWeek: programWeek,
            warmupOverride: warmupOverride,
            displayName: re.displayName,
            routineExerciseId: re.id,
            overrideRange: re.overrideRepMin != null && re.overrideRepMax != null ? RepRange(re.overrideRepMin!, re.overrideRepMax!) : null,
            supersetGroup: re.supersetGroup,
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
    Program? program,
    List<String> programSlots = const [],
    int programWeek = 2,
    int? warmupOverride,
    String? displayName,
    int? routineExerciseId,
    RepRange? overrideRange,
    int? supersetGroup,
  }) async {
    final exId = await _insertExerciseRow(
      sessionId: sessionId,
      info: info,
      position: position,
      range: overrideRange ?? range,
      targetSets: targetSets,
      restSeconds: restSeconds,
      targetRir: targetRir,
      coach: coach,
      program: program,
      programSlots: programSlots,
      programWeek: programWeek,
      warmupOverride: warmupOverride,
      displayName: displayName,
      overrideRange: overrideRange,
    );
    await (_db.update(_db.sessionExercises)..where((t) => t.id.equals(exId))).write(SessionExercisesCompanion(
      routineExerciseId: Value(routineExerciseId),
      supersetGroup: Value(supersetGroup),
    ));
    return exId;
  }

  Future<int> _insertExerciseRow({
    required int sessionId,
    required ExerciseInfo info,
    required int position,
    required RepRange range,
    required int targetSets,
    required int restSeconds,
    required int targetRir,
    required CoachContext coach,
    Program? program,
    List<String> programSlots = const [],
    int programWeek = 2,
    int? warmupOverride,
    String? displayName,
    RepRange? overrideRange,
  }) async {
    if (program != null && programSlots.isNotEmpty) {
      return _insertProgramExercise(
        overrideRange: overrideRange,
        sessionId: sessionId,
        info: info,
        position: position,
        targetSets: targetSets,
        restSeconds: restSeconds,
        coach: coach,
        program: program,
        slotIds: programSlots,
        week: programWeek,
        warmupOverride: warmupOverride,
        displayName: displayName,
      );
    }
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

  /// A routine row that follows a program: per-set prescriptions for the week (rep range, RIR,
  /// last-set technique), one suggestion per program slot (e.g. 2×4-6 heavy, then 1×20 back-off),
  /// and the program's warm-up pyramid from today's working weight.
  Future<int> _insertProgramExercise({
    required int sessionId,
    required ExerciseInfo info,
    required int position,
    required int targetSets,
    required int restSeconds,
    required CoachContext coach,
    required Program program,
    required List<String> slotIds,
    required int week,
    int? warmupOverride,
    String? displayName,
    RepRange? overrideRange,
  }) async {
    // A routine-level rep range (routine editor / "Update routine") replaces every slot's range.
    final prescriptions = [
      for (final p in prescribeSets(program: program, slotIds: slotIds, sets: targetSets, week: week))
        overrideRange == null ? p : p.withRange(overrideRange),
    ];
    // Group consecutive sets by slot, keeping order.
    final groups = <List<SetPrescription>>[];
    for (final p in prescriptions) {
      if (groups.isEmpty || groups.last.first.slotId != p.slotId) groups.add([]);
      groups.last.add(p);
    }
    final suggestions = [
      for (final g in groups) coach.suggest(info, g.first.repRange, g.length, g.first.targetRir ?? 0),
    ];
    final main = suggestions.first;
    final firstSlot = program.slot(groups.first.first.slotId)!;
    final headline = StringBuffer(main.headline);
    final why = [...main.why];
    for (var i = 1; i < groups.length; i++) {
      final s = suggestions[i];
      headline.write(' · then ${formatKg(s.weight)} kg × ${groups[i].first.repRange}');
      why.add('${groups[i].first.repRange} set(s): ${s.headline}');
    }
    final combined = Suggestion(
      kind: main.kind,
      weight: main.weight,
      reps: main.reps,
      sets: main.sets,
      rir: main.rir,
      headline: headline.toString(),
      why: why,
      techniqueDay: main.techniqueDay,
      rampUp: main.rampUp,
      band: main.band,
    );
    final exId = await _db.into(_db.sessionExercises).insert(SessionExercisesCompanion.insert(
          sessionId: sessionId,
          exerciseId: info.id,
          position: position,
          repMin: overrideRange?.min ?? firstSlot.repRange.min,
          repMax: overrideRange?.max ?? firstSlot.repRange.max,
          targetSets: targetSets,
          restSeconds: restSeconds,
          targetRir: Value(groups.first.first.targetRir ?? 0),
          suggestionKind: Value(main.kind.name),
          suggestedWeight: Value(main.weight),
          suggestedReps: Value(main.reps),
          suggestedSets: Value(main.sets),
          suggestionJson: Value(StoredSuggestion.encode(combined)),
          programSlots: Value(jsonEncode(slotIds)),
          programWeek: Value(week),
          displayName: Value(displayName),
        ));
    var pos = 0;
    // Warm-ups (not for calibration, where the lifter ramps up anyway).
    if (!main.rampUp) {
      final count = warmupOverride ?? warmupCountFor(firstSlot, firstOfDay: position == 0, compound: info.isCompound);
      for (final w in warmupSets(
        program: program,
        count: count,
        workingWeight: main.weight,
        increment: coach.increments.of(info.equipmentKind),
      )) {
        await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
              sessionExerciseId: exId,
              position: pos++,
              isWarmup: const Value(true),
              weight: Value(w.weight),
              reps: Value(w.reps),
              targetRepMin: Value(w.repRange.min),
              targetRepMax: Value(w.repRange.max),
            ));
      }
    }
    for (var g = 0; g < groups.length; g++) {
      final s = suggestions[g];
      // A Red technique day trims sets; keep the first ones of each slot.
      final take = s.techniqueDay ? s.sets.clamp(1, groups[g].length) : groups[g].length;
      for (var i = 0; i < take; i++) {
        final p = groups[g][i];
        await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
              sessionExerciseId: exId,
              position: pos++,
              weight: Value(s.weight),
              reps: Value(s.reps),
              suggestedWeight: Value(s.rampUp ? null : s.weight),
              suggestedReps: Value(s.reps),
              targetRepMin: Value(p.repRange.min),
              targetRepMax: Value(p.repRange.max),
              targetRir: Value(p.targetRir),
              technique: Value(p.technique),
            ));
      }
    }
    return exId;
  }

  /// Swaps a session exercise for [info] in the same position, keeping its program slots, set count
  /// and rest (the replacement inherits the prescription). Its sets are rebuilt with a fresh
  /// suggestion; any sets already logged on the old exercise are discarded.
  Future<int> replaceExercise({
    required ActiveExercise old,
    required ExerciseInfo info,
    required CoachContext coach,
    Program? program,
  }) {
    return _db.transaction(() async {
      final row = old.row;
      await (_db.delete(_db.workoutSets)..where((t) => t.sessionExerciseId.equals(row.id))).go();
      await (_db.delete(_db.sessionExercises)..where((t) => t.id.equals(row.id))).go();
      return _insertExercise(
        sessionId: row.sessionId,
        info: info,
        position: row.position,
        range: RepRange(row.repMin, row.repMax),
        targetSets: row.targetSets,
        restSeconds: row.restSeconds,
        targetRir: row.targetRir,
        coach: coach,
        program: program,
        programSlots: decodeSlots(row.programSlots),
        programWeek: row.programWeek ?? standardProgramWeek,
        displayName: info.name,
        routineExerciseId: row.routineExerciseId,
        overrideRange: row.targetsEdited ? RepRange(row.repMin, row.repMax) : null,
        supersetGroup: row.supersetGroup,
      );
    });
  }

  /// Mid-workout "Target reps": one range for every working set (drops and warm-ups keep theirs).
  Future<void> setTargetReps(ActiveExercise ex, RepRange range) => _db.transaction(() async {
        await (_db.update(_db.sessionExercises)..where((t) => t.id.equals(ex.row.id))).write(SessionExercisesCompanion(
          repMin: Value(range.min),
          repMax: Value(range.max),
          targetsEdited: const Value(true),
        ));
        final ids = [for (final s in ex.sets) if (!s.isWarmup && s.setType != 'drop') s.id];
        await (_db.update(_db.workoutSets)..where((t) => t.id.isIn(ids)))
            .write(WorkoutSetsCompanion(targetRepMin: Value(range.min), targetRepMax: Value(range.max)));
      });

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
          suggestedWeight: Value(warmup || (sug?.rampUp ?? false) ? null : (last?.suggestedWeight ?? sug?.weight)),
          suggestedReps: Value(warmup ? null : (last?.suggestedReps ?? sug?.reps)),
          // An added working set repeats the previous working set's prescription (never its technique).
          targetRepMin: Value(warmup ? null : last?.targetRepMin),
          targetRepMax: Value(warmup ? null : last?.targetRepMax),
          targetRir: Value(warmup ? null : last?.targetRir),
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

  /// Would completing this set with [weight] count as an override (more than 5 % above the suggestion)?
  bool wouldOverride(WorkoutSet set, double weight, {bool? isWarmup}) =>
      set.setType != 'drop' && _guardrail.isOverride(weight: weight, suggested: set.suggestedWeight, isWarmup: isWarmup ?? set.isWarmup);

  /// Section 7: a reason is asked for only when the set was too heavy, i.e. an override whose reps also
  /// fell below the bottom of its range. Failure inside the range is never flagged.
  bool needsReason(WorkoutSet set, {required double weight, required int reps, required int exerciseRepMin}) =>
      wouldOverride(set, weight) && reps < (set.targetRepMin ?? exerciseRepMin);

  /// Marks a set done. Ego sets (see [needsReason]) must carry a reason.
  Future<void> completeSet(
    WorkoutSet set, {
    required double weight,
    required int reps,
    required double? rpe,
    required bool isWarmup,
    OverrideReason? reason,
    required DateTime now,
    int? exerciseRepMin,
  }) async {
    final override = wouldOverride(set, weight, isWarmup: isWarmup);
    if (exerciseRepMin != null && needsReason(set, weight: weight, reps: reps, exerciseRepMin: exerciseRepMin) && reason == null) {
      throw StateError('A set that was too heavy (override below the rep range) needs a reason');
    }
    await (_db.update(_db.workoutSets)..where((t) => t.id.equals(set.id))).write(WorkoutSetsCompanion(
      weight: Value(weight),
      reps: Value(reps),
      rpe: Value(rpe),
      isWarmup: Value(isWarmup),
      completed: const Value(true),
      completedAt: Value(now),
      isOverride: Value(override),
      overrideReason: Value(override ? reason?.name : null),
    ));
  }

  /// SET-cell menu: working, warm-up (W), drop set (D) under the set before it, or a program technique.
  Future<void> setSetKind(WorkoutSet set, {required String kind}) async {
    final w = WorkoutSetsCompanion(
      isWarmup: Value(kind == 'warmup'),
      setType: Value(kind == 'drop' ? 'drop' : null),
      technique: Value(kind.startsWith('technique:') ? kind.substring('technique:'.length) : (kind == 'working' ? null : set.technique)),
      suggestedWeight: kind == 'warmup' || kind == 'drop' ? const Value(null) : const Value.absent(),
    );
    await (_db.update(_db.workoutSets)..where((t) => t.id.equals(set.id))).write(w);
  }

  Future<void> setRest(int sessionExerciseId, {bool? enabled, int? seconds}) =>
      (_db.update(_db.sessionExercises)..where((t) => t.id.equals(sessionExerciseId))).write(SessionExercisesCompanion(
        restEnabled: enabled == null ? const Value.absent() : Value(enabled),
        restSeconds: seconds == null ? const Value.absent() : Value(seconds),
      ));

  /// Links two exercises into one superset (A1/A2). Joining an exercise that's already in a group adds to it.
  Future<void> superset(ActiveExercise a, ActiveExercise b) async {
    final group = a.row.supersetGroup ?? b.row.supersetGroup ?? a.row.id;
    await (_db.update(_db.sessionExercises)..where((t) => t.id.isIn([a.row.id, b.row.id])))
        .write(SessionExercisesCompanion(supersetGroup: Value(group)));
  }

  Future<void> leaveSuperset(int sessionExerciseId) => (_db.update(_db.sessionExercises)..where((t) => t.id.equals(sessionExerciseId)))
      .write(const SessionExercisesCompanion(supersetGroup: Value(null)));

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
