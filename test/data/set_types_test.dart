import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/history.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/program/domain/program.dart';
import 'package:spotter/features/workout/data/routine_repository.dart';
import 'package:spotter/features/workout/data/session_repository.dart';
import 'package:spotter/features/workout/domain/set_kinds.dart';
import 'package:spotter/features/workout/domain/superset_rounds.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime(2026, 10, 12, 18);
  final coach = CoachContext(
    history: TrainingHistory.empty,
    readiness: null,
    overloaded: const {},
    freezes: const {},
    increments: Increments.defaults,
    now: now,
  );
  final program = Program.fromJson(jsonDecode(File('assets/programs/min_max_phase2.json').readAsStringSync()) as Map<String, dynamic>);

  group('drop weight', () {
    test('25 % off, rounded to the increment', () {
      expect(dropWeight(100, pct: 25, increment: 2.5), 75);
      expect(dropWeight(75, pct: 25, increment: 2.5), 57.5); // 56.25 → 57.5
      expect(dropWeight(40, pct: 20, increment: 5), 30); // 32 → 30
    });
    test('always at least one increment lighter, never negative', () {
      expect(dropWeight(5, pct: 20, increment: 5), 0);
      expect(dropWeight(2.5, pct: 20, increment: 2.5), 0);
      expect(dropWeight(0, pct: 25, increment: 2.5), 0);
    });
    test('assisted lifts drop by adding assistance', () {
      expect(dropWeight(-20, pct: 25, increment: 5), -25);
    });
  });

  group('LoggedSet follow-ups', () {
    test('myo and hold sets never count as working sets; holds add no volume', () {
      final log = ExerciseSessionLog(sessionId: 1, date: now, sets: const [
        LoggedSet(weight: 60, reps: 10, rpe: 10),
        LoggedSet(weight: 60, reps: 2, rpe: 10, isMyo: true),
        LoggedSet(weight: 60, reps: 30, isHold: true),
        LoggedSet(weight: 45, reps: 8, rpe: 10, isDrop: true),
      ]);
      expect(log.workingSets, hasLength(1));
      expect(log.volume, 60 * 10 + 60 * 2 + 45 * 8);
      expect(const LoggedSet(weight: 60, reps: 2, isMyo: true).isValidForRecords, isFalse);
    });
  });

  group('session', () {
    late AppDatabase db;
    late Map<String, ExerciseInfo> catalog;
    late SessionRepository sessions;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final ex = ExerciseRepository(db);
      await ex.ensureSeeded(
        jsonOverride: File('assets/exercises.json').readAsStringSync(),
        extraJsonOverride: File('assets/extra_exercises.json').readAsStringSync(),
        sourcesJsonOverride: File('assets/library_sources.json').readAsStringSync(),
      );
      catalog = await ex.watchCatalog().first;
      sessions = SessionRepository(db);
    });
    tearDown(() => db.close());

    Future<ActiveSession> active() async => (await sessions.watchActive().first)!;

    Future<ActiveSession> startWith(List<String> ids) async {
      final id = await sessions.start(name: 'T', coach: coach, catalog: catalog);
      for (final e in ids) {
        await sessions.addExercise(
          sessionId: id,
          info: catalog[e]!,
          range: const RepRange(8, 12),
          targetSets: 2,
          restSeconds: 90,
          targetRir: 1,
          coach: coach,
        );
      }
      return active();
    }

    test('several drops under one set, each 20 % under the one above; they follow the parent load', () async {
      final s = await startWith(['Barbell_Curl']);
      var ex = s.exercises.single;
      final first = ex.sets.firstWhere((x) => x.isWorkingSet);
      await sessions.updateSet(first.id, weight: 40);
      ex = (await active()).exercises.single;
      final parent = ex.sets.firstWhere((x) => x.id == first.id);
      await sessions.addFollowUp(ex, parent, SetKind.drop, increment: 2.5);
      ex = (await active()).exercises.single;
      await sessions.addFollowUp(ex, parent, SetKind.drop, increment: 2.5);
      ex = (await active()).exercises.single;
      final order = ex.sets.where((x) => !x.isWarmup).map((x) => (x.kind, x.weight)).toList();
      expect(order.take(3), [(SetKind.working, 40.0), (SetKind.drop, 32.5), (SetKind.drop, 25.0)]);
      expect(order[3].$1, SetKind.working, reason: 'set 2 stays after the drops of set 1');

      await sessions.updateSet(first.id, weight: 50);
      await sessions.refreshDrops(first.id, increment: 2.5);
      ex = (await active()).exercises.single;
      expect(ex.sets.where((x) => x.kind == SetKind.drop).map((x) => x.weight), [40, 32.5]);
    });

    test('myo cycle and hold keep the load; added working sets copy the working set, not a drop', () async {
      final s = await startWith(['Barbell_Curl']);
      var ex = s.exercises.single;
      final parent = ex.sets.lastWhere((x) => x.isWorkingSet);
      await sessions.addFollowUp(ex, parent, SetKind.myo, increment: 2.5);
      ex = (await active()).exercises.single;
      await sessions.addFollowUp(ex, parent, SetKind.hold, increment: 2.5);
      ex = (await active()).exercises.single;
      final myo = ex.sets.firstWhere((x) => x.kind == SetKind.myo);
      final hold = ex.sets.firstWhere((x) => x.kind == SetKind.hold);
      expect((myo.weight, myo.reps), (parent.weight, myoRepsPerCycle));
      expect((hold.weight, hold.reps), (parent.weight, holdSeconds));
      await sessions.addFollowUp(ex, parent, SetKind.drop, increment: 2.5);
      ex = (await active()).exercises.single;
      await sessions.addSet(ex);
      ex = (await active()).exercises.single;
      expect(ex.sets.last.isWorkingSet, isTrue);
      expect(ex.sets.last.weight, parent.weight);
    });

    test('program techniques pre-create their follow-ups (week 8: two 25 % drops on Leg Curl)', () async {
      final routines = RoutineRepository(db);
      final rid = await routines.create('Lower', now: now);
      final slot = program.slot('lower_01')!;
      await db.into(db.routineExercises).insert(RoutineExercisesCompanion.insert(
            routineId: rid,
            exerciseId: 'Lying_Leg_Curls',
            position: 0,
            repMin: slot.repRange.min,
            repMax: slot.repRange.max,
            targetSets: slot.workingSets,
            restSeconds: 90,
            programSlots: const Value('["lower_01"]'),
          ));
      final r = await routines.watchRoutine(rid).first;
      await sessions.start(name: 'Lower', coach: coach, catalog: catalog, routine: r, program: program, programWeek: 8);
      final ex = (await active()).exercises.single;
      final kinds = ex.sets.where((x) => !x.isWarmup).map((x) => x.kind).toList();
      expect(kinds, [...List.filled(slot.workingSets, SetKind.working), SetKind.drop, SetKind.drop]);
      final last = ex.sets.lastWhere((x) => x.isWorkingSet);
      final drops = ex.sets.where((x) => x.kind == SetKind.drop).toList();
      expect(drops.first.weight, lessThan(last.weight == 0 ? 1 : last.weight));
      expect(drops.every((d) => d.technique == dropTechnique), isTrue);
    });

    test('superset: sets alternate A1, A2 by round; rest only when the round is done', () async {
      var s = await startWith(['Barbell_Curl', 'Hammer_Curls']);
      await sessions.superset(s.exercises[0], s.exercises[1]);
      s = await active();
      final a = s.exercises[0], b = s.exercises[1];
      final order = supersetOrder(s.exercises).where((x) => !x.isWarmup).map((x) => x.sessionExerciseId).toList();
      expect(order, [a.row.id, b.row.id, a.row.id, b.row.id]);
      final a1 = a.sets.firstWhere((x) => x.isWorkingSet);
      final b1 = b.sets.firstWhere((x) => x.isWorkingSet);
      expect(supersetRoundDone(s.exercises, a.row.id, a1.id), isFalse, reason: 'B still to go');
      await sessions.completeSet(a1, weight: a1.weight, reps: a1.reps, rpe: 9, isWarmup: false, now: now, exerciseRepMin: 8);
      s = await active();
      expect(supersetRoundDone(s.exercises, b.row.id, b1.id), isTrue);
    });
  });
}
