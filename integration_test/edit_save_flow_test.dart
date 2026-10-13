import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/import/domain/liftoff.dart' show lbPerKg;
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';
import 'logger_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Edited KG / REPS are what gets saved: ✓ with the keypad open, REPS only, KG → NEXT → REPS, ✓ on a different set, '
      'collapse and minimize', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await startPush(h);
    final sets = await activeSets(h);
    final fly = sets['High-to-Low Cable Fly']!;
    final press = sets['Seated Smith Machine Shoulder Press']!;
    final bench = sets['Smith Machine Bench Press']!;

    debugPrint('STEP type KG, ✓ at once with the keypad still open');
    await openCell(h, fly[0], 'kg');
    await typeOnKeypad(h, '37.5');
    await checkSet(h, fly[0]);
    var r = await setRow(h, fly[0].id);
    expect(r.completed, isTrue);
    expect(r.weight, 37.5, reason: 'typed KG saved');
    expect(r.reps, fly[0].reps, reason: 'untouched REPS keeps the suggestion');

    debugPrint('STEP type REPS only, ✓');
    await openCell(h, fly[1], 'reps');
    await typeOnKeypad(h, '9');
    await checkSet(h, fly[1]);
    r = await setRow(h, fly[1].id);
    expect(r.completed, isTrue);
    expect(r.reps, 9, reason: 'typed REPS saved');
    expect(r.weight, fly[1].weight, reason: 'untouched KG keeps the suggestion');

    debugPrint('STEP KG → NEXT → REPS → ✓');
    await h.scrollToTop();
    await openCell(h, press[0], 'kg');
    await typeOnKeypad(h, '42.5');
    await h.tap(find.byKey(const ValueKey('key-next')));
    await typeOnKeypad(h, '7');
    await checkSet(h, press[0]);
    r = await setRow(h, press[0].id);
    expect(r.completed, isTrue);
    expect((r.weight, r.reps), (42.5, 7), reason: 'both typed values saved');

    debugPrint('STEP type on one set, ✓ on a different set: the typed value is kept, the other set is completed');
    await openCell(h, press[1], 'kg');
    await typeOnKeypad(h, '30');
    await checkSet(h, bench[0]);
    r = await setRow(h, press[1].id);
    expect(r.weight, 30, reason: 'the value typed on the other set was not lost');
    expect(r.completed, isFalse);
    expect((await setRow(h, bench[0].id)).completed, isTrue);

    debugPrint('STEP type, then collapse the exercise');
    await h.scrollToTop();
    await openCell(h, bench[1], 'reps');
    await typeOnKeypad(h, '12');
    await h.tap(find.descendant(of: blockOf('Smith Machine Bench Press'), matching: find.byTooltip('Collapse')));
    expect((await setRow(h, bench[1].id)).reps, 12, reason: 'collapsing commits the typed value');

    debugPrint('STEP type, then minimize the workout');
    final legExt = sets['Single Leg Extension']!;
    await openCell(h, legExt[0], 'reps');
    await typeOnKeypad(h, '6');
    await h.scrollToTop();
    await h.tap(find.byTooltip('Minimize workout'));
    await h.waitFor(find.byKey(const ValueKey('mini-workout-bar')));
    expect((await setRow(h, legExt[0].id)).reps, 6, reason: 'minimizing commits the typed value');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Type a value, then Finish: that set is saved with what was typed', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await startPush(h);
    final fly = (await activeSets(h))['High-to-Low Cable Fly']!;

    await openCell(h, fly[0], 'kg');
    await typeOnKeypad(h, '20');
    await h.tap(find.byKey(const ValueKey('key-next')));
    await typeOnKeypad(h, '11');
    await checkSet(h, fly[0]);
    // The next set: typed but never ✓, then Finish.
    await openCell(h, fly[1], 'kg');
    await typeOnKeypad(h, '22.5');
    await h.scrollToTop();
    await h.tap(find.text('Finish'));
    if (find.text('Finish workout?').evaluate().isNotEmpty) {
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
    }
    await h.waitFor(find.text('WORKOUT COMPLETE'), timeout: const Duration(seconds: 30), reason: 'summary');

    final saved = (await tester.runAsync(() => (h.db!.select(h.db!.workoutSets)..where((t) => t.completed.equals(true))).get()))!;
    final byId = {for (final s in saved) s.id: s};
    expect(byId[fly[0].id]!.weight, 20);
    expect(byId[fly[0].id]!.reps, 11);
    expect(byId[fly[1].id], isNotNull, reason: 'the set whose KG was typed before Finish is part of the workout');
    expect(byId[fly[1].id]!.weight, 22.5, reason: 'typed KG saved by Finish');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('PREV copy replaces what was typed (no stale typed value overwrites it later)', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      final t = DateTime.now().subtract(const Duration(days: 3));
      String two(int v) => v.toString().padLeft(2, '0');
      final d = '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
      String lb(double kg) => (kg * lbPerKg).toStringAsFixed(6);
      const dur = '01 hours 00 minutes 00 seconds';
      final csv = 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
          '$d,$dur,,High to Low Cable Fly,0,${lb(12)},12,0,0,,10-12\n'
          '$d,$dur,,High to Low Cable Fly,1,${lb(12)},11,0,0,,10-12\n';
      await s.commit(await s.preview(csv, catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    await startPush(h);
    final fly = (await activeSets(h))['High-to-Low Cable Fly']!.where((s) => !s.isWarmup).toList();

    await openCell(h, fly[0], 'kg');
    await typeOnKeypad(h, '99');
    await h.tap(find.byKey(ValueKey('prev-${fly[0].id}')));
    await checkSet(h, fly[0]);
    final r = await setRow(h, fly[0].id);
    expect((r.weight, r.reps), (12.0, 12), reason: 'PREV copy won over the earlier typed 99');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('A saved set that equals the suggestion is flagged on its session and can be corrected by tapping it', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final db = h.db!;
    // A workout from before this build: a ✓ that saved the suggestion (40 × 8) where 42.5 × 7 was typed.
    final before = DateTime.now().subtract(const Duration(days: 1));
    final sid = (await tester.runAsync(() async {
      final id = await db.into(db.sessions).insert(SessionsCompanion.insert(
          name: 'Upper', startedAt: before, endedAt: Value(before.add(const Duration(hours: 1))), status: const Value('finished')));
      final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
          sessionId: id, exerciseId: 'Barbell_Curl', displayName: const Value('Barbell Curl'), position: 0, repMin: 6, repMax: 8, targetSets: 2, restSeconds: 90));
      for (var i = 0; i < 2; i++) {
        await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
            sessionExerciseId: ex,
            position: i,
            weight: Value(i == 0 ? 40 : 45),
            reps: Value(i == 0 ? 8 : 6),
            suggestedWeight: const Value(40),
            suggestedReps: const Value(8),
            rpe: const Value(9),
            completed: const Value(true),
            completedAt: Value(before)));
      }
      return id;
    }))!;
    await h.pumpApp();
    final setIds = (await tester.runAsync(() => (db.select(db.workoutSets)..orderBy([(t) => OrderingTerm.asc(t.position)])).get()))!.map((e) => e.id).toList();

    await h.goTab(Icons.insights_outlined);
    await h.tap(find.descendant(of: find.byType(TabBar), matching: find.text('History')));
    await h.settle(8);
    await h.tap(find.text('Upper').first);
    await h.waitFor(find.byKey(const ValueKey('suspect-sets-card')), reason: 'one set is exactly the suggestion', scroll: false);
    expect(find.textContaining('1 set below is exactly the suggestion'), findsOneWidget);
    expect(find.text('= the suggestion · tap to correct'), findsOneWidget, reason: 'only the first set (45 × 6 was a real edit)');
    await h.shot('suspect-sets');

    await h.tap(find.byKey(ValueKey('hist-set-${setIds[0]}')));
    await h.waitFor(find.byKey(const ValueKey('correct-kg')), scroll: false);
    await tester.enterText(find.byKey(const ValueKey('correct-kg')), '42.5');
    await tester.enterText(find.byKey(const ValueKey('correct-reps')), '7');
    await h.tap(find.byKey(const ValueKey('correct-save')));
    await h.settle(8);
    final fixed = (await tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.id.equals(setIds[0]))).getSingle()))!;
    expect((fixed.weight, fixed.reps), (42.5, 7));
    expect(find.byKey(const ValueKey('suspect-sets-card')), findsNothing, reason: 'corrected: no longer a candidate');
    expect(sid, isPositive);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
