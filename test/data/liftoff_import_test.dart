import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/gamification/domain/stats.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/import/domain/liftoff_mapping.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/ranks/data/rank_exclusions.dart';
import 'package:spotter/features/workout/data/history_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final csv = File('test/fixtures/liftoff_sample.csv').readAsStringSync();
  final now = DateTime(2026, 10, 12, 9);

  late AppDatabase db;
  late Map<String, ExerciseInfo> catalog;
  late LiftoffImportService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await bootstrapDatabase(db);
    catalog = await ExerciseRepository(db).watchCatalog().first;
    service = LiftoffImportService(db);
  });
  tearDown(() => db.close());

  test('preview: sessions, sets, date range, mappings, unmatched', () async {
    final p = await service.preview(csv, catalog: catalog);
    expect(p.parse.sessions.length, 2);
    expect(p.newSessions.length, 2);
    expect(p.newSets, 9);
    expect(p.first, DateTime(2026, 9, 1, 8));
    expect(p.last, DateTime(2026, 9, 3, 18, 30));
    expect(p.mappingFor('Chest Press').method, MatchMethod.routine);
    expect(p.mappingFor('Assisted Pull Ups').exerciseId, 'sp_assisted_pull_up_machine');
    expect(p.mappingFor('Dragon Flag').method, MatchMethod.custom);
    expect(p.unmatched.map((m) => m.liftoffName), ['Zercher Good Morning Hop']);
  });

  test('commit writes finished imported sessions; re-import is a no-op', () async {
    final p = await service.preview(csv, catalog: catalog);
    final r = await service.commit(p, catalog: catalog, settings: const SettingsModel(), now: now);
    expect(r.sessions, 2);
    expect(r.sets, 9);
    expect(r.customsCreated, 2); // Dragon Flag (name map) + the unmatched name

    final sessions = await (db.select(db.sessions)..orderBy([(t) => OrderingTerm.asc(t.startedAt)])).get();
    expect(sessions.map((s) => s.source), ['liftoff', 'liftoff']);
    expect(sessions.first.name, 'Upper', reason: 'most exercises belong to the Upper routine');
    expect(sessions.first.endedAt, DateTime(2026, 9, 1, 9, 10));
    expect(sessions.every((s) => s.xpEarned == 0), isTrue);
    expect(await db.getSetting(liftoffImportedAtKey), now.toIso8601String());

    final sets = await db.select(db.workoutSets).get();
    expect(sets.every((s) => s.completed && s.suggestedWeight == null && !s.isOverride), isTrue);
    expect(sets.where((s) => s.rpe == 10).length, 8, reason: 'to failure unless the file has an RPE');
    expect(sets.where((s) => s.rpe == 8).length, 1);

    final history = await HistoryRepository(db).load(await ExerciseRepository(db).watchCatalog().first);
    final press = history.sessions.first.exercises.first;
    expect(press.name, 'Chest Press');
    expect(press.range, const RepRange(6, 8));
    expect(press.sets.map((s) => s.targetRange), const [RepRange(6, 8), RepRange(6, 8), RepRange(20, 20)]);
    expect(press.sets.first.set.weight, closeTo(60, 1e-3));
    final pull = history.sessions.last.exercises.first;
    expect(pull.sets.first.set.weight, closeTo(-30, 1e-3), reason: 'Liftoff assistance → negative load');
    expect(history.sessions.every((s) => s.imported), isTrue);
    expect(disciplineLast30(history, now), isNull, reason: 'imported sets never count for discipline');

    // Same file again: nothing new.
    final again = await service.preview(csv, catalog: await ExerciseRepository(db).watchCatalog().first);
    expect(again.alreadyImported, 2);
    expect(again.newSessions, isEmpty);
    final r2 = await service.commit(again, catalog: catalog, settings: const SettingsModel(), now: now);
    expect(r2.sessions, 0);
    expect((await db.select(db.sessions).get()).length, 2);
    expect((await db.select(db.workoutSets).get()).length, 9);
  });

  test('suggestions come from recent imported performance', () async {
    final cat = (await ExerciseRepository(db).watchCatalog().first);
    final p = await service.preview(csv, catalog: cat);
    await service.commit(p, catalog: cat, settings: const SettingsModel(), now: now);
    final history = await HistoryRepository(db).load(await ExerciseRepository(db).watchCatalog().first);
    final ctx = CoachContext(
      history: history,
      readiness: null,
      overloaded: const {},
      freezes: const {},
      increments: Increments.defaults,
      now: now,
    );
    // Chest press 60 kg × 10, 8 at 6–8 to failure (failure prescribed): top of the range → +1 increment.
    final s = ctx.suggest(cat['Leverage_Chest_Press']!, const RepRange(6, 8), 2, 0);
    expect(s.kind, SuggestionKind.increase);
    expect(s.weight, 62.5);
    // The 20-rep back-off set only informs a 20-rep slot.
    final b = ctx.suggest(cat['Leverage_Chest_Press']!, const RepRange(20, 20), 1, 0);
    expect(b.kind, SuggestionKind.increase);
    expect(b.weight, 42.5);
    // A slot range never done is re-anchored from recent e1RM.
    final r = ctx.suggest(cat['Leverage_Chest_Press']!, const RepRange(10, 12), 2, 1);
    expect(r.kind, SuggestionKind.seeded);
  });

  test('the bundled map sends every Liftoff Shoulder Press to the barbell press', () async {
    const csv3 = 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
        '2026-06-01 08:00:00,00 hours 50 minutes 00 seconds,,Shoulder Press,0,198.416035967,6,0,0,,\n';
    final p = await service.preview(csv3, catalog: catalog);
    expect(p.mappingFor('Shoulder Press').exerciseId, 'Barbell_Shoulder_Press');
    expect(p.mappingFor('Shoulder Press').weightRules, isEmpty);
  });

  test('weight-banded names pick the exercise per session; excluded names stay out of ranking', () async {
    const csv2 = 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
        '2026-05-01 08:00:00,00 hours 50 minutes 00 seconds,,Shoulder Press,0,66.1386786555,8,0,0,,\n'
        '2026-05-01 08:00:00,00 hours 50 minutes 00 seconds,,Cable Kickback,0,4.4092452437,30,0,0,,\n'
        '2026-06-01 08:00:00,00 hours 50 minutes 00 seconds,,Shoulder Press,0,198.416035967,6,0,0,,\n';
    // A by_weight entry (supported, though the owner's map no longer needs one) plus the bundled
    // Cable Kickback entry.
    final bundled = await LiftoffImportService.loadNameMap();
    final map = LiftoffNameMap.parse(jsonEncode({
      'map': {
        'Shoulder Press': {
          'by_weight': [
            {'min_kg': 80, 'id': 'Machine_Shoulder_Military_Press', 'name': 'Machine Shoulder Press'},
            {'min_kg': 0, 'id': 'Barbell_Shoulder_Press', 'name': 'Barbell Shoulder Press'},
          ],
        },
        'Cable Kickback': {'id': 'One-Legged_Cable_Kickback', 'exclude_from_ranks': bundled.excludeFromRanks.contains('Cable Kickback')},
      },
    }));
    final p = await service.preview(csv2, catalog: catalog, nameMap: map);
    expect(p.mappingFor('Shoulder Press').weightRules, hasLength(2));
    await service.commit(p, catalog: catalog, settings: const SettingsModel(), now: now);
    final rows = await (db.select(db.sessionExercises)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    final press = rows.where((r) => r.exerciseId != 'One-Legged_Cable_Kickback').toList();
    expect(press.map((r) => r.exerciseId), ['Barbell_Shoulder_Press', 'Machine_Shoulder_Military_Press']);
    expect(press.map((r) => r.displayName), ['Barbell Shoulder Press', 'Machine Shoulder Press']);
    expect(await RankExclusions(db).load(), {'One-Legged_Cable_Kickback'});
  });
}
