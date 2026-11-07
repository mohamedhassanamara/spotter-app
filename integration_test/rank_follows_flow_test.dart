import 'package:drift/drift.dart' show OrderingTerm, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';
import 'logger_helpers.dart';

/// Ranks follow added and swapped exercises (in-memory database, real taps).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String label(WidgetTester t, String id) => t.widget<Text>(find.byKey(ValueKey('rank-strip-label-$id'))).data!;

  testWidgets('add a never-done exercise → rank row at once; ✓ ranks it live and it persists after Finish; swap rebinds', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '80');
    final db = h.db!;
    await startPush(h);
    debugPrint('STEP add Hammer Curls (in no routine): the rank row exists at once: Unranked, Bronze 1 target');
    await h.tap(find.text('Add exercise'));
    await h.waitFor(find.byType(TextField), scroll: false);
    await tester.enterText(find.byType(TextField).first, 'hammer');
    await h.settle(6);
    await h.waitFor(find.text('Hammer Curls'));
    await h.tap(find.text('Hammer Curls').first);
    await h.waitFor(find.text('Hammer Curls'), reason: 'added mid-workout');
    final hammer = (await tester.runAsync(() => (db.select(db.sessionExercises)..orderBy([(t) => OrderingTerm.desc(t.id)])).get()))!.first;
    final id = hammer.exerciseId;
    await h.waitFor(find.byKey(ValueKey('rank-strip-label-$id')));
    expect(label(tester, id), 'Unranked');
    expect(find.descendant(of: find.byKey(ValueKey('rank-gap-$id')), matching: find.textContaining('Bronze 1')), findsOneWidget);
    expect(find.byKey(const ValueKey('rank-mode-toggle')), findsWidgets);
    await h.deviceShot('rank-row-unranked');

    debugPrint('STEP ✓ a first set: the badge and progress appear in real time');
    final hammerSets = (await tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(hammer.id))).get()))!
        .where((s) => !s.isWarmup)
        .toList();
    await h.waitFor(find.byKey(ValueKey('set-${hammerSets[0].id}')));
    await openCell(h, hammerSets[0], 'kg');
    await typeOnKeypad(h, '20');
    await openCell(h, hammerSets[0], 'reps');
    await typeOnKeypad(h, '10');
    await checkSet(h, hammerSets[0]);
    if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    await h.waitFor(find.byKey(ValueKey('rank-strip-label-$id')));
    await h.settle(10);
    expect(label(tester, id), isNot('Unranked'));
    expect(label(tester, id), matches(RegExp(r'^[A-Z][a-z]+( \d)?$')));
    final ranked = label(tester, id);
    await h.deviceShot('rank-row-ranked');

    debugPrint('STEP Bodyweight mode: one line, "x BW", same card height');
    final cardBefore = tester.getSize(find.byKey(ValueKey('rank-strip-label-$id'))).height;
    await h.tap(find.byKey(const ValueKey('rank-target-mode-bodyweight')).first);
    await h.settle(6);
    final gap = tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('rank-gap-$id')), matching: find.byType(Text)));
    expect(gap.data, contains('x BW'));
    expect(gap.maxLines, 1);
    expect(tester.getSize(find.byKey(ValueKey('rank-strip-label-$id'))).height, cardBefore);
    await h.deviceShot('rank-row-bodyweight');
    await h.tap(find.byKey(ValueKey('rank-row-line2-$id')));
    await h.waitFor(find.byKey(const ValueKey('rank-detail-sheet')), scroll: false);
    await h.deviceShot('rank-row-detail');
    await tester.tapAt(const Offset(10, 60));
    await h.settle(6);
    await h.tap(find.byKey(const ValueKey('rank-target-mode-lift')).first);

    debugPrint('STEP the first completed set created the rank record; it persists after Finish');
    await h.scrollToTop();
    await h.tap(find.text('Finish'));
    if (find.text('Finish workout?').evaluate().isNotEmpty) {
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
    }
    await h.waitFor(find.text('Keep routine as is'), scroll: false);
    await h.tap(find.text('Keep routine as is'));
    await h.waitForSummary();
    await h.passRankScreens();
    final saved = (await tester.runAsync(() => db.customSelect(
            'SELECT COUNT(*) AS n FROM workout_sets w JOIN session_exercises se ON se.id = w.session_exercise_id WHERE se.exercise_id = ? AND w.completed = 1',
            variables: [Variable<String>(id)]).getSingle()))!
        .read<int>('n');
    expect(saved, 1);
    await h.expectNoLoggedErrors();
    expect(ranked, isNotEmpty);
    await h.dispose();
  });

  testWidgets('swap in a routine workout: the new exercise gets its own rank row; logged sets stay with the original', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '80');
    final db = h.db!;
    await startPush(h);
    final sets = await activeSets(h);
    final fly = sets['High-to-Low Cable Fly']!;
    final row = (await tester.runAsync(() => (db.select(db.sessionExercises)..where((t) => t.id.equals(fly.first.sessionExerciseId))).getSingle()))!;

    debugPrint('STEP log a set on the original, then Replace it by Hammer Curls: ask "Move logged sets?", answer No');
    await openCell(h, fly[0], 'kg');
    await typeOnKeypad(h, '20');
    await openCell(h, fly[0], 'reps');
    await typeOnKeypad(h, '10');
    await checkSet(h, fly[0]);
    if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    await h.scrollToTop();
    await h.tap(find.byKey(ValueKey('menu-${row.id}')));
    await h.tap(find.text('Replace').last);
    await h.waitFor(find.text('Search the library'), scroll: false);
    await h.tap(find.text('Search the library'));
    await h.waitFor(find.byType(TextField), scroll: false);
    await tester.enterText(find.byType(TextField).first, 'hammer');
    await h.settle(6);
    await h.waitFor(find.text('Hammer Curls'));
    await h.tap(find.text('Hammer Curls').first);
    await h.waitFor(find.byKey(const ValueKey('move-logged-dialog')), scroll: false);
    await h.tap(find.byKey(const ValueKey('move-logged-no')));
    await h.settle(8);

    final exs = (await tester.runAsync(() => (db.select(db.sessionExercises)..orderBy([(t) => OrderingTerm.asc(t.position)])).get()))!;
    final hammer = exs.firstWhere((e) => e.displayName == 'Hammer Curls');
    expect((await setRow(h, fly[0].id)).sessionExerciseId, row.id, reason: 'the logged set stays on the original');
    await h.waitFor(find.byKey(ValueKey('rank-strip-label-${hammer.exerciseId}')));
    expect(label(tester, hammer.exerciseId), 'Unranked', reason: 'the new exercise ranks on its own');
    await h.deviceShot('rank-row-after-swap');
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
