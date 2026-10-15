import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/data_fixes.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const lunge = 'sp_db_walking_lunge';

  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await bootstrapDatabase(db);
  });
  tearDown(() => db.close());

  Future<int> addSet(String source, double kg) async {
    final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(
        name: 'T', startedAt: DateTime(2026, 9, 1), source: Value(source), status: const Value('finished')));
    final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
        sessionId: sid, exerciseId: lunge, position: 0, repMin: 10, repMax: 10, targetSets: 1, restSeconds: 90));
    return db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
        sessionExerciseId: ex, position: 0, weight: Value(kg), reps: const Value(10), completed: const Value(true)));
  }

  Future<double> weightOf(int id) async => (await (db.select(db.workoutSets)..where((t) => t.id.equals(id))).getSingle()).weight;

  test('imported Walking Lunge sets are halved once; in-app sets stay', () async {
    final imported = await addSet('liftoff', 35);
    final inApp = await addSet('app', 17.5);
    await db.deleteSetting(DataFixes.lungeKey);
    await DataFixes.runAll(db);
    expect(await weightOf(imported), 17.5);
    expect(await weightOf(inApp), 17.5);
    await DataFixes.runAll(db); // guarded: a second run changes nothing
    expect(await weightOf(imported), 17.5);
  });

  test('a new Liftoff import logs the lunge per dumbbell', () async {
    const csv = 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
        '2026-09-01 08:00:00,01 hours 00 minutes 00 seconds,,Walking Lunge,0,77.1617918,20,0,0,,10 per leg\n';
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    final service = LiftoffImportService(db);
    final p = await service.preview(csv, catalog: catalog);
    await service.commit(p, catalog: catalog, settings: const SettingsModel(), now: DateTime(2026, 10, 12));
    final w = await (db.select(db.workoutSets)).get();
    expect(w.single.weight, closeTo(17.5, 0.01));
    expect(w.single.reps, 10);
  });

  test('the lunge ranks on the per-dumbbell standard; the combined standard is gone', () async {
    final standards = await RanksRepository.loadStandards();
    expect(standards.any((s) => s.id == 'dumbbell_walking_lunge'), isFalse);
    final s = standards.firstWhere((s) => s.exerciseIds.contains(lunge));
    expect(s.id, 'dumbbell_lunge');
    expect(s.perHand, isTrue);
  });
}
