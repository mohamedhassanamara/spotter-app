import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/domain/gym.dart';
import '../../../core/domain/training.dart';
import '../../coach/data/coach_context.dart';
import '../../coach/domain/guardrail.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../library/domain/exercise_info.dart';
import '../../readiness/domain/readiness.dart';
import '../../program/data/program_repository.dart';
import '../../program/domain/program.dart';
import '../../ranks/data/rank_exclusions.dart';
import '../domain/equipment_resnap.dart';
import '../domain/set_kinds.dart';
import 'routine_repository.dart';

/// Suggestion as stored with a session exercise.
extension on String {
  String? ifEmpty() => isEmpty ? null : this;
}

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
    this.formResetHint,
    this.maxReached = false,
    this.downNote,
    this.lighterOption,
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

  /// The engine thinks the last session was a deliberate step down: the weight a form reset would
  /// restart from.
  final double? formResetHint;

  /// The target is the machine's max load: only reps can progress.
  final bool maxReached;

  /// "↓ from 10 kg: reason" when the target is below last time's weight; shown inline, always.
  final String? downNote;

  /// A lighter weight the lifter may choose after three sessions below the range (never applied for them).
  final double? lighterOption;

  static String encode(Suggestion s) => jsonEncode({
        'headline': s.headline,
        'why': s.why,
        'technique': s.techniqueDay,
        'ramp': s.rampUp,
        'band': s.band.name,
        if (s.formResetHint != null) 'reset': s.formResetHint,
        if (s.maxReached) 'max': true,
        if (s.downNote != null) 'down': s.downNote,
        if (s.lighterOption != null) 'lighter': s.lighterOption,
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
      formResetHint: (j['reset'] as num?)?.toDouble(),
      maxReached: j['max'] as bool? ?? false,
      downNote: j['down'] as String?,
      lighterOption: (j['lighter'] as num?)?.toDouble(),
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

  /// One set read straight from the database. The [watchActive] stream (and so `activeSessionProvider`)
  /// can still hold the value from before a write that has just finished, so anything that has to act on
  /// what was *just* saved (✓, Finish) must read here.
  Future<WorkoutSet?> workoutSet(int id) => (_db.select(_db.workoutSets)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The in-progress session read straight from the database (see [workoutSet]).
  Future<ActiveSession?> loadActive() => watchActive().first;

  Future<Session?> activeSession() =>
      (_db.select(_db.sessions)..where((t) => t.status.equals('active'))..limit(1)).getSingleOrNull();

  /// Starts a session, from a routine or empty, computing a suggestion for each exercise.
  Future<int> start({
    required String name,
    required CoachContext coach,
    required Map<String, ExerciseInfo> catalog,
    RoutineWithExercises? routine,
    Program? program,
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
        // Routine superset groups become the session id of the group's first exercise (no clashes with
        // groups made mid-workout, which use session exercise ids too).
        final groups = <int, int>{};
        for (final re in routine.exercises) {
          final info = catalog[re.exerciseId];
          if (info == null) continue;
          final exId = await _insertExercise(
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
            warmupOverride: warmupOverride,
            displayName: re.displayName,
            routineExerciseId: re.id,
            overrideRange: re.overrideRepMin != null && re.overrideRepMax != null ? RepRange(re.overrideRepMin!, re.overrideRepMax!) : null,
            supersetGroup: re.supersetGroup,
          );
          final g = re.supersetGroup;
          if (g != null) {
            await (_db.update(_db.sessionExercises)..where((t) => t.id.equals(exId)))
                .write(SessionExercisesCompanion(supersetGroup: Value(groups[g] ??= exId)));
          }
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

  /// A routine row that follows a program: per-set prescriptions from the canonical week (rep range, RIR,
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
    int? warmupOverride,
    String? displayName,
    RepRange? overrideRange,
  }) async {
    // A routine-level rep range (routine editor / "Update routine") replaces every slot's range.
    final prescriptions = [
      for (final p in prescribeSets(program: program, slotIds: slotIds, sets: targetSets))
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
      formResetHint: main.formResetHint,
      maxReached: main.maxReached,
      downNote: [
        if (main.downNote != null) main.downNote!,
        for (var i = 1; i < groups.length; i++)
          if (suggestions[i].downNote != null) '${groups[i].first.repRange} sets: ${suggestions[i].downNote}',
      ].join('\n').ifEmpty(),
      lighterOption: main.lighterOption,
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
              // Warm-ups land on weights that exist too.
              weight: Value(main.weight > 0 ? coach.gridFor(info).snap(w.weight) : w.weight),
              reps: Value(w.reps),
              targetRepMin: Value(w.repRange.min),
              targetRepMax: Value(w.repRange.max),
            ));
      }
    }
    for (var g = 0; g < groups.length; g++) {
      final s = suggestions[g];
      // Every prescribed set, always: coaching inputs change targets, never the routine's volume.
      for (var i = 0; i < groups[g].length; i++) {
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
        displayName: info.name,
        routineExerciseId: row.routineExerciseId,
        overrideRange: row.targetsEdited ? RepRange(row.repMin, row.repMax) : null,
        supersetGroup: row.supersetGroup,
      );
    });
  }

  /// The optional "Lighter option: X kg" chip (after three sessions below the range): the not-yet-done working sets of
  /// [ex] move to [weight], marked and explained like any other change; the done ones stay as logged.
  Future<void> applyLighterOption(ActiveExercise ex, double weight) async {
    for (final set in ex.sets) {
      if (set.completed || !set.isWorkingSet || (set.weight - weight).abs() < 0.01) continue;
      await (_db.update(_db.workoutSets)..where((t) => t.id.equals(set.id))).write(WorkoutSetsCompanion(
        weight: Value(weight),
        suggestedWeight: Value(weight),
        adjustedFrom: Value(set.adjustedFrom ?? set.weight),
        adjustReason: Value('You chose the lighter option (${formatKg(weight)} kg) after three sessions below the rep range at ${formatKg(set.adjustedFrom ?? set.weight)} kg.'),
      ));
    }
  }

  /// A Weight steps change (starting weight, step, load type, max load) in the middle of a workout: the one exception to the frozen plan.
  /// The not-yet-completed sets of [ex] snap to the new [grid] and cap at the max load at once; completed sets stay as logged. Each changed set
  /// is marked like any other changed target, with the reason. [newSuggested] is an optional replacement for the old suggestion (without it every set snaps to the nearest load).
  Future<int> applyEquipmentChange(ActiveExercise ex, {required WeightGrid grid, double? newSuggested}) async {
    final plan = planResnap(sets: ex.sets, grid: grid, oldSuggested: ex.row.suggestedWeight, newSuggested: newSuggested);
    if (plan.isEmpty) return 0;
    await _db.transaction(() async {
      for (final r in plan) {
        await (_db.update(_db.workoutSets)..where((t) => t.id.equals(r.setId))).write(WorkoutSetsCompanion(
          weight: Value(r.weight),
          suggestedWeight: r.suggested == null ? const Value.absent() : Value(r.suggested),
          adjustedFrom: Value(r.from),
          adjustReason: Value(r.reason),
        ));
      }
      final old = ex.row.suggestedWeight;
      final target = newSuggested ?? (old == null ? null : grid.snap(old));
      if (target != null && old != null && (target - old).abs() >= 0.01) {
        await (_db.update(_db.sessionExercises)..where((t) => t.id.equals(ex.row.id))).write(SessionExercisesCompanion(suggestedWeight: Value(target)));
      }
    });
    return plan.length;
  }

  /// Mid-workout "Target reps": one range for every working set (drops and warm-ups keep theirs).
  Future<void> setTargetReps(ActiveExercise ex, RepRange range) => _db.transaction(() async {
        await (_db.update(_db.sessionExercises)..where((t) => t.id.equals(ex.row.id))).write(SessionExercisesCompanion(
          repMin: Value(range.min),
          repMax: Value(range.max),
          targetsEdited: const Value(true),
        ));
        final ids = [for (final s in ex.sets) if (s.isWorkingSet) s.id];
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
    final last = ex.sets.where((s) => !s.isFollowUp).lastOrNull;
    final sug = ex.suggestion;
    final weight = warmup
        ? ((sug?.weight ?? last?.weight ?? 0) * 0.5)
        : (last?.weight ?? sug?.weight ?? 0);
    final position = warmup ? -1 - ex.sets.where((s) => s.isWarmup).length : (ex.sets.lastOrNull?.position ?? -1) + 1;
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

  /// Undo of [deleteSet]: puts the row back with its id and values, at its old place in the list.
  Future<void> restoreSet(WorkoutSet set) async {
    await _db.customUpdate(
      'UPDATE workout_sets SET position = position + 1 WHERE session_exercise_id = ? AND position >= ?',
      variables: [Variable.withInt(set.sessionExerciseId), Variable.withInt(set.position)],
      updates: {_db.workoutSets},
    );
    await _db.into(_db.workoutSets).insert(set, mode: InsertMode.insertOrReplace);
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
      !set.isFollowUp && _guardrail.isOverride(weight: weight, suggested: set.suggestedWeight, isWarmup: isWarmup ?? set.isWarmup);

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
    DateTime? restEndedAt,
  }) async {
    final override = wouldOverride(set, weight, isWarmup: isWarmup);
    if (exerciseRepMin != null && needsReason(set, weight: weight, reps: reps, exerciseRepMin: exerciseRepMin) && reason == null) {
      throw StateError('A set that was too heavy (override below the rep range) needs a reason');
    }
    // The rest actually taken before this set: from the previous done set of the exercise to this ✓, or to the moment the
    // rest timer was skipped (then it is over, whatever came after).
    int? rest;
    if (set.setType == null) {
      final before = (await _setsOf(set.sessionExerciseId))
          .where((x) => x.completed && x.completedAt != null && x.setType == null && x.position < set.position)
          .lastOrNull;
      if (before != null) {
        final end = restEndedAt != null && restEndedAt.isAfter(before.completedAt!) && !restEndedAt.isAfter(now) ? restEndedAt : now;
        rest = end.difference(before.completedAt!).inSeconds.clamp(0, 3 * 3600);
      }
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
      restSeconds: Value(rest),
    ));
    // A real working set (not a warm-up, a drop / myo / hold, or an empty one) switches the exercise on for ranks.
    if (!isWarmup && reps > 0 && set.setType == null) {
      final ex = await (_db.select(_db.sessionExercises)..where((t) => t.id.equals(set.sessionExerciseId))).getSingleOrNull();
      if (ex != null) await RankExclusions(_db).autoEnable(ex.exerciseId);
    }
  }

  /// The only thing allowed to change a plan during a workout: after a working set falls short of its
  /// rep range, the *later, untouched working sets of the same exercise* move one available step lighter so
  /// they can stay in range. Sets you already edited, done sets, drop sets and warm-ups never change; the
  /// weight never goes up. The changed sets keep the original weight and the reason (the ⓘ marker).
  /// Returns the sets that changed.
  Future<List<int>> adaptLaterSets(WorkoutSet done, {required WeightGrid? grid, required int exerciseRepMin}) async {
    if (done.isWarmup || done.isFollowUp || done.weight <= 0 || done.reps <= 0 || grid == null) return const [];
    final min = done.targetRepMin ?? exerciseRepMin;
    if (done.reps >= min) return const [];
    final lighter = grid.previous(done.weight);
    if (lighter == null) return const [];
    final sets = await _setsOf(done.sessionExerciseId);
    final number = sets.where((s) => s.isWorkingSet).toList().indexWhere((s) => s.id == done.id) + 1;
    final max = done.targetRepMax;
    final range = max == null ? '$min+' : '$min–$max';
    final changed = <int>[];
    for (final s in sets) {
      if (s.position <= done.position || s.completed || !s.isWorkingSet) continue;
      final planned = s.suggestedWeight;
      // Untouched: still at its planned weight, and heavier than the step down.
      if (planned == null || (s.weight - planned).abs() > 0.01 || s.weight <= lighter + 0.01) continue;
      await (_db.update(_db.workoutSets)..where((t) => t.id.equals(s.id))).write(WorkoutSetsCompanion(
        weight: Value(lighter),
        suggestedWeight: Value(lighter),
        adjustedFrom: Value(s.adjustedFrom ?? s.weight),
        adjustReason: Value('Set $number: ${done.reps} reps at ${formatKg(done.weight)} kg, below the $range rep range. '
            'This set moves one step lighter (${formatKg(s.adjustedFrom ?? s.weight)} → ${formatKg(lighter)} kg) so it can stay in range.'),
      ));
      changed.add(s.id);
    }
    return changed;
  }

  /// SET-cell menu: working, warm-up (W), drop (D), myo-rep cycle (M), static hold (H), or a program technique.
  Future<void> setSetKind(WorkoutSet set, {required String kind}) async {
    final k = kind.startsWith('technique:') ? SetKind.working : SetKind.fromId(kind);
    final w = WorkoutSetsCompanion(
      isWarmup: Value(k == SetKind.warmup),
      setType: Value(k.setType),
      technique: Value(kind.startsWith('technique:') ? kind.substring('technique:'.length) : (k == SetKind.working ? null : set.technique)),
      suggestedWeight: k == SetKind.working ? const Value.absent() : const Value(null),
      reps: k == SetKind.hold ? const Value(holdSeconds) : (k == SetKind.myo ? const Value(myoRepsPerCycle) : const Value.absent()),
      targetRepMin: k.isFollowUp ? const Value(null) : const Value.absent(),
      targetRepMax: k.isFollowUp ? const Value(null) : const Value.absent(),
    );
    await (_db.update(_db.workoutSets)..where((t) => t.id.equals(set.id))).write(w);
  }

  /// Adds a follow-up under [parent] (after any already there): a drop set [dropPct] % lighter than the
  /// set above it, rounded to [increment]; a myo-rep cycle (same load, 2 reps); a static hold (same load,
  /// 30 s). Program drop sets carry their technique id so a later load change re-derives them at 25 %.
  Future<int> addFollowUp(ActiveExercise ex, WorkoutSet parent, SetKind kind,
          {required double increment, WeightGrid? grid, int? dropPct, String? technique}) =>
      _db.transaction(() async {
        final sets = await _setsOf(ex.row.id);
        final i = sets.indexWhere((s) => s.id == parent.id);
        var anchor = parent;
        for (final s in sets.skip(i + 1)) {
          if (!s.isFollowUp) break;
          anchor = s;
        }
        final pct = dropPct ?? (technique == dropTechnique ? programDropPct : defaultDropPct);
        final from = kind == SetKind.drop && anchor.setType == 'drop' ? anchor.weight : parent.weight;
        await _shiftAfter(ex.row.id, anchor.position, 1);
        final id = await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
              sessionExerciseId: ex.row.id,
              position: anchor.position + 1,
              setType: Value(kind.setType),
              weight: Value(kind == SetKind.drop ? _drop(from, pct, increment, grid) : parent.weight),
              reps: Value(switch (kind) {
                SetKind.myo => myoRepsPerCycle,
                SetKind.hold => holdSeconds,
                _ => parent.reps,
              }),
              targetRir: const Value(0),
              technique: Value(technique),
            ));
        await _renumber(ex.row.id);
        return id;
      });

  /// After the load of [parent] changes: its not-yet-done drop sets follow, each [pct] % under the one above.
  Future<void> refreshDrops(int parentId, {required double increment, WeightGrid? grid}) => _db.transaction(() async {
        final parent = await (_db.select(_db.workoutSets)..where((t) => t.id.equals(parentId))).getSingleOrNull();
        if (parent == null || parent.isFollowUp) return;
        final sets = await _setsOf(parent.sessionExerciseId);
        var from = parent.weight;
        for (final s in sets.skip(sets.indexWhere((x) => x.id == parent.id) + 1)) {
          if (!s.isFollowUp) break;
          if (s.setType != 'drop') continue;
          if (!s.completed) {
            final pct = s.technique == dropTechnique ? programDropPct : defaultDropPct;
            final w = _drop(from, pct, increment, grid);
            await (_db.update(_db.workoutSets)..where((t) => t.id.equals(s.id))).write(WorkoutSetsCompanion(weight: Value(w)));
            from = w;
          } else {
            from = s.weight;
          }
        }
      });

  /// A drop's load: [pct] % lighter, on a weight that exists (always at least one step lighter).
  static double _drop(double from, int pct, double increment, WeightGrid? grid) {
    final w = dropWeight(from, pct: pct, increment: increment);
    if (grid == null) return w;
    final snapped = grid.snapDown(w);
    return snapped < from - 0.01 ? snapped : (grid.previous(from) ?? w);
  }

  Future<List<WorkoutSet>> _setsOf(int sessionExerciseId) => (_db.select(_db.workoutSets)
        ..where((t) => t.sessionExerciseId.equals(sessionExerciseId))
        ..orderBy([(t) => OrderingTerm.asc(t.position), (t) => OrderingTerm.asc(t.id)]))
      .get();

  Future<void> _shiftAfter(int sessionExerciseId, int position, int by) => _db.customUpdate(
        'UPDATE workout_sets SET position = position + ? WHERE session_exercise_id = ? AND position > ?',
        variables: [Variable.withInt(by), Variable.withInt(sessionExerciseId), Variable.withInt(position)],
        updates: {_db.workoutSets},
      );

  /// Section 7: "+ partials" on a set (toggle).
  Future<void> setPartials(int setId, bool on) =>
      (_db.update(_db.workoutSets)..where((t) => t.id.equals(setId))).write(WorkoutSetsCompanion(partials: Value(on)));

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
          restSeconds: Value(null),
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
