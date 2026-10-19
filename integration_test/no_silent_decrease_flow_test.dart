import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';
import 'logger_helpers.dart';

String _csv() {
  String d(int daysAgo) {
    final t = DateTime.now().subtract(Duration(days: daysAgo));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
  }

  const dur = '01 hours 00 minutes 00 seconds';
  final rows = <String>[];
  // Chest Press: 65 kg, below the 4–6 range three sessions in a row.
  for (final days in [20, 13, 6]) {
    rows.add('${d(days)},$dur,,Chest Press,0,143.3,3,0,0,,4-6');
    rows.add('${d(days)},$dur,,Chest Press,1,143.3,3,0,0,,4-6');
  }
  // Machine Chest Fly: 50 kg at the top of its range last time.
  rows.add('${d(6)},$dur,,Machine Chest Fly,0,110.2,12,0,0,,10-12');
  rows.add('${d(6)},$dur,,Machine Chest Fly,1,110.2,12,0,0,,10-12');
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n${rows.join('\n')}\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('No silent decreases: missing reps hold the weight with an optional lighter chip; a decrease is always shown inline', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final db = h.db!;
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(db).watchCatalog().first;
      final s = LiftoffImportService(db);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
      // An active ego flag on the fly: the one deliberate way down.
      await db.into(db.egoFreezes).insert(EgoFreezesCompanion.insert(
          exerciseId: 'Butterfly', startedAt: DateTime.now(), until: DateTime.now().add(const Duration(days: 3)), baseWeight: 50, reason: 'test'));
    });
    await h.pumpApp();
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    final active = (await tester.runAsync(() => (db.select(db.sessions)..where((t) => t.status.equals('active'))).getSingle()))!;
    final exs = (await tester.runAsync(() => (db.select(db.sessionExercises)..where((t) => t.sessionId.equals(active.id))).get()))!;
    final chest = exs.firstWhere((e) => e.exerciseId == 'Leverage_Chest_Press');
    final fly = exs.firstWhere((e) => e.exerciseId == 'Butterfly');

    debugPrint('STEP three sessions below the range: the weight is HELD (65 kg) and a lighter option is offered, not applied');
    final chestSets = (await tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(chest.id))).get()))!;
    expect(chestSets.where((s) => !s.isWarmup).first.weight, closeTo(65, 0.5), reason: 'held, not lowered');
    await h.waitFor(find.byKey(ValueKey('lighter-option-${chest.id}')), reason: 'optional lighter chip');
    expect(find.descendant(of: find.byKey(ValueKey('lighter-option-${chest.id}')), matching: find.text('Lighter option: 60 kg')), findsOneWidget);
    expect(find.byKey(ValueKey('down-note-${chest.id}')), findsNothing, reason: 'nothing was lowered');
    await h.shot('lighter-option-chip');

    debugPrint('STEP the chip applies the lighter weight to the sets you have not done, with the marker and the reason');
    await h.tap(find.byKey(ValueKey('lighter-option-${chest.id}')));
    await h.settle(4);
    final after = (await tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(chest.id))).get()))!;
    final working = after.where((s) => !s.isWarmup).toList();
    expect(working.every((s) => (s.weight - 60).abs() < 0.01), isTrue, reason: 'all open working sets moved to 60 kg');
    expect(working.first.adjustReason, contains('lighter option'));
    await h.waitFor(find.byKey(ValueKey('adjusted-${working.first.id}')), reason: 'the target-changed marker');

    debugPrint('STEP an ego flag lowers the fly: visible inline without opening ⓘ, with the reason');
    await h.scrollToTop();
    await h.waitFor(find.byKey(ValueKey('down-note-${fly.id}')), reason: 'inline decrease note');
    final note = tester.widget<Text>(find.byKey(ValueKey('down-note-${fly.id}'))).data!;
    expect(note, startsWith('↓ from 50 kg: ego flag'));
    final flySet = (await tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(fly.id))).get()))!.firstWhere((s) => !s.isWarmup);
    expect(flySet.weight, lessThan(50));
    await h.shot('inline-decrease-note');
    expect(find.byKey(ValueKey('why-${fly.id}')), findsNothing, reason: 'the ⓘ panel is closed');
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
