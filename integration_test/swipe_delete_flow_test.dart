import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:spotter/core/db/database.dart';

import 'harness.dart';
import 'logger_helpers.dart';

Future<int> countSets(AppHarness h, int exerciseId) async => (await h.tester.runAsync(() =>
        (h.db!.select(h.db!.workoutSets)..where((t) => t.sessionExerciseId.equals(exerciseId))).get()))!
    .length;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Swipe left deletes a set (Delete action and full swipe), Undo restores it, swipe right completes, '
      'the page never scrolls sideways', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await startPush(h);
    final sets = await activeSets(h);
    final fly = sets['High-to-Low Cable Fly']!;
    final exId = fly.first.sessionExerciseId;
    final before = await countSets(h, exId);
    expect(before, greaterThanOrEqualTo(2));

    Finder row(WorkoutSet s) => find.byKey(ValueKey('swipe-row-${s.id}'));
    Future<void> show(WorkoutSet s) async {
      await tester.ensureVisible(row(s));
      await h.settle(3);
    }

    debugPrint('STEP partial swipe reveals a red Delete with a trash icon; tapping it deletes');
    await show(fly[0]);
    final scrollable = tester.state<ScrollableState>(find.ancestor(of: row(fly[0]), matching: find.byType(Scrollable)).first);
    final offsetBefore = scrollable.position.pixels;
    await tester.drag(row(fly[0]), const Offset(-110, 0));
    await h.settle(6);
    expect(find.byKey(ValueKey('swipe-delete-${fly[0].id}')), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('swipe-delete-${fly[0].id}')), matching: find.byIcon(Icons.delete_outline_rounded)), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('swipe-delete-${fly[0].id}')), matching: find.text('Delete')), findsOneWidget);
    expect(scrollable.position.pixels, offsetBefore, reason: 'a horizontal swipe never scrolls the page');
    await h.shot('swipe-delete-revealed');
    await h.tap(find.byKey(ValueKey('swipe-delete-${fly[0].id}')));
    await h.settle(8);
    expect(await countSets(h, exId), before - 1);
    expect(find.byKey(const ValueKey('set-deleted-snackbar')), findsOneWidget);

    debugPrint('STEP Undo brings the set back with its values and place');
    await h.tap(find.text('Undo'));
    await h.settle(8);
    expect(await countSets(h, exId), before);
    final back = await setRow(h, fly[0].id);
    expect((back.weight, back.reps, back.position), (fly[0].weight, fly[0].reps, fly[0].position));

    debugPrint('STEP full swipe deletes at once; the Undo snackbar goes away after 3 s');
    await show(fly[1]);
    await tester.drag(row(fly[1]), const Offset(-400, 0));
    await h.settle(10);
    expect(await countSets(h, exId), before - 1);
    expect(find.byKey(const ValueKey('set-deleted-snackbar')), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('set-deleted-snackbar')), findsNothing, reason: 'auto-dismissed after 3 s');
    final left = (await tester.runAsync(() => (h.db!.select(h.db!.workoutSets)
          ..where((t) => t.sessionExerciseId.equals(exId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get()))!;
    expect([for (final s in left) s.position], [for (var i = 0; i < left.length; i++) i], reason: 'positions stay gap-free');

    debugPrint('STEP swipe right completes a set (and springs back)');
    await show(fly[0]);
    await tester.drag(row(fly[0]), const Offset(120, 0));
    await h.settle(8);
    expect((await setRow(h, fly[0].id)).completed, isTrue);

    debugPrint('STEP the set-menu Delete still works (fallback)');
    final victim = sets['Smith Machine Bench Press']!.first;
    final benchEx = victim.sessionExerciseId;
    final benchBefore = await countSets(h, benchEx);
    await show(victim);
    await h.tap(find.byKey(ValueKey('set-label-${victim.id}')));
    await h.tap(find.text('Delete set'));
    await h.settle(8);
    expect(await countSets(h, benchEx), benchBefore - 1);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Swipe-delete works on warm-up, drop, myo and hold rows', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await startPush(h);
    final db = h.db!;
    final fly = (await activeSets(h))['High-to-Low Cable Fly']!;
    final exId = fly.first.sessionExerciseId;
    final ids = <String, int>{};
    await tester.runAsync(() async {
      var pos = 100;
      for (final kind in ['warmup', 'drop', 'myo', 'hold']) {
        ids[kind] = await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
              sessionExerciseId: exId,
              position: pos++,
              isWarmup: Value(kind == 'warmup'),
              setType: Value(kind == 'warmup' ? null : kind),
              weight: const Value(10),
              reps: const Value(8),
            ));
      }
    });
    await h.settle(10);
    var n = await countSets(h, exId);
    for (final kind in ['warmup', 'drop', 'myo', 'hold']) {
      debugPrint('STEP swipe-delete a $kind row');
      final row = find.byKey(ValueKey('swipe-row-${ids[kind]}'));
      await h.waitFor(row, reason: '$kind row shown');
      await tester.ensureVisible(row);
      await h.settle(3);
      await tester.drag(row, const Offset(-400, 0));
      await h.settle(10);
      n -= 1;
      expect(await countSets(h, exId), n, reason: '$kind deleted');
    }
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
