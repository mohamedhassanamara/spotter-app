import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Variable, Value, BooleanExpressionOperators, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/data_fixes.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/program/data/program_repository.dart';
import 'package:spotter/features/workout/data/history_repository.dart';
import 'package:spotter/features/workout/data/routine_repository.dart';
import 'package:spotter/features/workout/data/session_repository.dart';

/// The owner's real Walking Lunge rows from the Liftoff export (test/fixtures/walking_lunge_real.csv: 35 kg on 7 Oct was
/// BOTH dumbbells), plus the Lower workouts logged in the app afterwards, which had followed that history:
/// 35 kg "per dumbbell" and a stored suggestion of 37.5 kg. The first fix only converted the imported rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const lunge = DataFixes.lungeExerciseId;
  final csv = File('test/fixtures/walking_lunge_real.csv').readAsStringSync();

  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await bootstrapDatabase(db);
  });
  tearDown(() => db.close());

  Future<List<WorkoutSet>> allLungeSets() async {
    final q = db.select(db.workoutSets).join([]);
    final rows = await db.customSelect(
      '''SELECT w.* FROM workout_sets w JOIN session_exercises se ON se.id = w.session_exercise_id
         WHERE se.exercise_id = ? ORDER BY w.id''',
      variables: [Variable.withString(lunge)],
    ).get();
    expect(q, isNotNull);
    return [for (final r in rows) db.workoutSets.map(r.data)];
  }

  /// A finished (or active) in-app session with one lunge exercise logged at [kg].
  Future<int> inAppSession({required DateTime at, required double kg, bool active = false, bool done = true, double? storedSuggestion}) async {
    final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(
        name: 'Lower', startedAt: at, status: Value(active ? 'active' : 'finished'), endedAt: Value(active ? null : at.add(const Duration(hours: 1)))));
    final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
        sessionId: sid,
        exerciseId: lunge,
        position: 0,
        repMin: 10,
        repMax: 10,
        targetSets: 1,
        restSeconds: 90,
        suggestedWeight: Value(storedSuggestion),
        suggestionJson: storedSuggestion == null
            ? const Value.absent()
            : Value('{"headline":"Today: ${storedSuggestion.toString().replaceAll('.0', '')} kg × 10, 1 set","why":["Rule: next available weight ${storedSuggestion.toString().replaceAll('.0', '')} kg."],"technique":false,"ramp":false,"band":"green"}')));
    await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
        sessionExerciseId: ex,
        position: 0,
        weight: Value(kg),
        reps: const Value(10),
        completed: Value(done),
        suggestedWeight: Value(storedSuggestion ?? kg),
        suggestedReps: const Value(10)));
    return ex;
  }

  Future<void> importReal() async {
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    final s = LiftoffImportService(db);
    await s.commit(await s.preview(csv, catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime(2026, 10, 12, 9));
  }

  /// Today's suggestion the way the app makes it: start the Lower routine and read the lunge row.
  Future<(double, String)> todaysSuggestion() async {
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    final routines = await RoutineRepository(db).watchRoutines().first;
    final lower = routines.firstWhere((r) => r.exercises.any((e) => e.exerciseId == lunge));
    final coach = CoachContext(
      history: await HistoryRepository(db).load(catalog),
      readiness: null,
      overloaded: const {},
      freezes: const {},
      increments: Increments.defaults,
      now: DateTime(2026, 10, 19, 9),
      bodyweight: 106,
    );
    final id = await SessionRepository(db).start(name: 'Lower', coach: coach, catalog: catalog, routine: lower, program: await ProgramRepository.load());
    final ex = await (db.select(db.sessionExercises)..where((t) => t.sessionId.equals(id) & t.exerciseId.equals(lunge))).getSingle();
    final sets = await (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(ex.id))..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final stored = StoredSuggestion.fromRow(ex)!;
    final weight = sets.where((s) => !s.isWarmup).first.weight;
    expect(ex.suggestedWeight, closeTo(weight, 0.01), reason: 'the stored suggestion and the set agree');
    await SessionRepository(db).discard(id);
    return (weight, stored.headline);
  }

  test('real export: every imported Walking Lunge set is stored per dumbbell, the heaviest 17.5 kg', () async {
    await importReal();
    final w = (await allLungeSets()).map((s) => s.weight).toList()..sort();
    expect(w.length, 6);
    expect(w, [closeTo(5, 0.01), closeTo(6.25, 0.01), closeTo(7.5, 0.01), closeTo(10, 0.01), closeTo(15, 0.01), closeTo(17.5, 0.01)]);
    expect(w.last, closeTo(17.5, 0.01), reason: '35 kg total → 17.5 per dumbbell (Liftoff stores pounds, so a few decimals)');
  });

  test('after the real export alone, today\'s suggestion is about 17.5 kg (not 37.5)', () async {
    await importReal();
    final (weight, headline) = await todaysSuggestion();
    expect(weight, inInclusiveRange(17.5, 20));
    expect(weight, lessThan(25));
    expect(headline, contains('17.5 kg'));
  });

  test('the case that stuck: in-app Lower workouts logged at 35 and a stale 37.5 suggestion are converted too', () async {
    await importReal();
    // Pre-fix state of the phone: the first fix had run (flags set), but the in-app sessions kept the total-load numbers.
    await inAppSession(at: DateTime(2026, 10, 14, 10), kg: 35, storedSuggestion: 37.5);
    await inAppSession(at: DateTime(2026, 10, 16, 9), kg: 37.5, storedSuggestion: 37.5);
    final activeEx = await inAppSession(at: DateTime(2026, 10, 18, 9), kg: 37.5, active: true, done: false, storedSuggestion: 37.5);
    await db.deleteSetting(DataFixes.lungeV2Key);
    final changed = await DataFixes.ensureLungeInAppSets(db);
    expect(changed, 3);
    final w = (await allLungeSets()).map((s) => s.weight).toList();
    expect(w.where((x) => x > 20), isEmpty, reason: 'nothing above 20 kg per dumbbell is left');
    expect((await allLungeSets()).where((s) => s.suggestedWeight != null && s.suggestedWeight! > 20), isEmpty);
    final stale = await (db.select(db.sessionExercises)..where((t) => t.id.equals(activeEx))).getSingle();
    expect(stale.suggestedWeight, 17.5, reason: 'the plan frozen in the workout that was already started');
    expect(stale.suggestionJson, contains('17.5 kg'));
    expect(stale.suggestionJson, isNot(contains('37.5')));
    // And once more is a no-op.
    expect(await DataFixes.ensureLungeInAppSets(db), 0);
    expect((await allLungeSets()).map((s) => s.weight).toList(), w);
  });

  test('after the fix the suggestion built from that history is about 17.5 kg, and per-dumbbell sets logged since stay untouched', () async {
    await importReal();
    await inAppSession(at: DateTime(2026, 10, 14, 10), kg: 35, storedSuggestion: 37.5);
    await db.deleteSetting(DataFixes.lungeV2Key);
    await DataFixes.runAll(db);
    await inAppSession(at: DateTime(2026, 10, 17, 10), kg: 17.5, storedSuggestion: 17.5);
    await DataFixes.runAll(db); // guarded: the new 17.5 kg set is not halved
    expect((await allLungeSets()).where((s) => s.weight == 17.5).length, greaterThanOrEqualTo(2), reason: 'the 17.5 kg set logged since (and the converted 35) stay at 17.5, not 8.75');
    expect((await allLungeSets()).where((s) => s.weight > 8 && s.weight < 9), isEmpty);
    final (weight, headline) = await todaysSuggestion();
    expect(weight, inInclusiveRange(15, 20));
    expect(headline, anyOf(contains('17.5 kg'), contains('20 kg')));
    expect(weight, lessThan(25));
  });
}
