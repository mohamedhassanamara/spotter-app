import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';

import 'harness.dart';
import 'logger_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Weight steps mid-workout: the sets not done yet follow the new starting weight, step and max load; the done set stays; the change is marked', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await h.goTab(Icons.fitness_center_outlined);
    await h.scrollToTop();
    await h.waitFor(find.text('Start'));
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    final sets = await activeSets(h);
    final fly = sets['Machine Chest Fly']!;
    final exId = fly.first.sessionExerciseId;

    // The plan the workout started with: 60 kg on every set (what the coach suggested on the old 5 kg grid).
    await tester.runAsync(() async {
      await (h.db!.update(h.db!.workoutSets)..where((t) => t.sessionExerciseId.equals(exId)))
          .write(const WorkoutSetsCompanion(weight: Value(60), suggestedWeight: Value(60), reps: Value(8)));
      await (h.db!.update(h.db!.sessionExercises)..where((t) => t.id.equals(exId))).write(const SessionExercisesCompanion(suggestedWeight: Value(60)));
    });
    await h.settle(8);
    Future<List<WorkoutSet>> rows() async =>
        (await tester.runAsync(() => (h.db!.select(h.db!.workoutSets)..where((t) => t.sessionExerciseId.equals(exId))..orderBy([(t) => OrderingTerm.asc(t.position)])).get()))!;
    final live = (await rows()).where((s) => !s.isWarmup).toList();

    debugPrint('STEP the first working set is done at 60 kg');
    await checkSet(h, live[0]);
    await h.settle(4);

    debugPrint('STEP Weight steps… → first plate 7, step 5: the open sets move onto 7, 12, 17 …, the done one stays at 60');
    final before = {for (final s in (await rows()).where((s) => !s.isWarmup && !s.completed)) s.id: s.weight};
    double near(double w) {
      final lo = 7 + 5 * ((w - 7) / 5).floor();
      return (w - lo) <= (lo + 5 - w) ? lo.toDouble() : lo + 5.0;
    }

    await h.scrollToTop();
    await h.tap(find.byKey(ValueKey('menu-$exId')));
    await h.tap(find.text('Weight steps…').last);
    await h.waitFor(find.byKey(const ValueKey('stack-start')), scroll: false);
    await tester.enterText(find.byKey(const ValueKey('stack-start')), '7');
    await tester.enterText(find.byKey(const ValueKey('stack-step')), '5');
    await h.tap(find.byKey(const ValueKey('stack-save')));
    for (var i = 0; i < 40; i++) {
      if ((await rows()).where((s) => !s.isWarmup && !s.completed).every((s) => s.weight == near(before[s.id]!))) break;
      await h.settle(4);
    }
    var now = (await rows()).where((s) => !s.isWarmup).toList();
    expect(now[0].weight, 60, reason: 'the done set is as logged');
    expect(now[0].completed, isTrue);
    expect(now[0].adjustReason, isNull);
    for (final s in now.skip(1)) {
      expect(s.weight, near(before[s.id]!), reason: 'the nearest of 7, 12, 17 … to ${before[s.id]} (${s.adjustReason})');
      expect((s.weight - 7) % 5, 0, reason: 'on the new grid');
      expect(s.adjustedFrom, 60, reason: 'the marker keeps what the workout started with');
      expect(s.adjustReason, startsWith('Weight steps updated'));
    }
    await h.scrollToTop();
    await h.waitFor(find.byKey(ValueKey('adjusted-${now[1].id}')), reason: 'the "target changed" marker on the changed set');
    await h.shot('weight-steps-marker');

    debugPrint('STEP the marker sits on the set number, never on KG / REPS: both cells stay tappable on every row, at the smallest iPhone width');
    final dpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = Size(375 * dpr, 667 * dpr); // iPhone SE
    addTearDown(tester.view.resetPhysicalSize);
    await h.settle(8);
    await h.scrollToTop();
    for (final s in now.skip(1)) {
      final dot = find.byKey(ValueKey('adjusted-${s.id}'));
      final caption = find.byKey(ValueKey('adjusted-caption-${s.id}'));
      await h.waitFor(dot, reason: 'marker on set ${s.id}');
      expect(caption, findsOneWidget, reason: 'one-line caption under the row');
      expect(find.descendant(of: caption, matching: find.text('Target updated · why?')), findsOneWidget);
      for (final f in ['kg', 'reps']) {
        final cell = find.byKey(ValueKey('cell-$f-${s.id}'));
        expect(tester.getRect(dot).overlaps(tester.getRect(cell)), isFalse, reason: 'the dot is off the $f cell');
        expect(tester.getRect(caption).overlaps(tester.getRect(cell)), isFalse, reason: 'the caption is under the row, off the $f cell');
        expect(tester.getSize(cell).height, greaterThanOrEqualTo(34));
        expect(tester.getSize(cell).width, greaterThanOrEqualTo(44), reason: '$f cell wide enough to hit at 375 pt');
        await openCell(h, s, f);
        await h.tap(find.byKey(const ValueKey('key-hide')));
      }
    }
    for (final s in (await rows()).where((x) => x.isWarmup || x.adjustReason == null).take(3)) {
      for (final f in ['kg', 'reps']) {
        final cell = find.byKey(ValueKey('cell-$f-${s.id}'));
        if (cell.evaluate().isEmpty || s.completed) continue;
        await openCell(h, s, f);
        await h.tap(find.byKey(const ValueKey('key-hide')));
      }
    }
    await h.shot('weight-steps-marker-small');
    // Tapping the caption opens the same explanation as the dot.
    await h.tap(find.byKey(ValueKey('adjusted-caption-${now[1].id}')));
    await h.waitFor(find.byKey(ValueKey('adjusted-dialog-${now[1].id}')), scroll: false);
    await h.tap(find.text('OK'));
    tester.view.resetPhysicalSize();
    await h.settle(8);
    await h.tap(find.byKey(ValueKey('adjusted-${now[1].id}')));
    await h.waitFor(find.byKey(ValueKey('adjusted-dialog-${now[1].id}')), scroll: false);
    expect(find.textContaining('Weight steps updated'), findsWidgets);
    await h.tap(find.text('OK'));

    debugPrint('STEP Weight steps… → max load 50: the open sets cap at 47 (the heaviest load of the grid under 50), the done one is untouched');
    await h.scrollToTop();
    await h.tap(find.byKey(ValueKey('menu-$exId')));
    await h.tap(find.text('Weight steps…').last);
    await h.waitFor(find.byKey(const ValueKey('max-load')), scroll: false);
    await tester.enterText(find.byKey(const ValueKey('max-load')), '50');
    await h.tap(find.byKey(const ValueKey('stack-save')));
    for (var i = 0; i < 40; i++) {
      if ((await rows()).where((s) => !s.isWarmup && !s.completed).every((s) => s.weight == 47)) break;
      await h.settle(4);
    }
    now = (await rows()).where((s) => !s.isWarmup).toList();
    expect(now[0].weight, 60);
    for (final s in now.skip(1)) {
      expect(s.weight, 47);
      expect(s.adjustedFrom, 60, reason: 'the marker keeps what it was when the workout started');
      expect(s.adjustReason, contains('max load is 50'));
    }

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
