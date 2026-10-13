import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/features/ranks/data/rank_exclusions.dart';

import 'harness.dart';
import 'logger_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A completed working set of an exercise that is off switches it on; a manual off stays off; '
      'an empty set and a warm-up do not', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final db = h.db!;
    Future<RankPolicy> policy() async => (await tester.runAsync(() => RankExclusions(db).policy()))!;
    await startPush(h);
    final sets = await activeSets(h);
    final fly = sets['High-to-Low Cable Fly']!;

    debugPrint('STEP add Hammer Curls (in no routine): off until a working set is done');
    await h.tap(find.text('Add exercise'));
    await h.waitFor(find.byType(TextField), scroll: false);
    await tester.enterText(find.byType(TextField).first, 'hammer');
    await h.settle(6);
    await h.waitFor(find.text('Hammer Curls'));
    await h.tap(find.text('Hammer Curls').first);
    await h.waitFor(find.text('Hammer Curls'), reason: 'added mid-workout');
    final hammer = (await tester.runAsync(() => (db.select(db.sessionExercises)..orderBy([(t) => OrderingTerm.desc(t.id)])).get()))!.first;
    expect((await policy()).sourceOf(hammer.exerciseId), RankSource.off);
    final hammerSets = (await tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(hammer.id))).get()))!
        .where((s) => !s.isWarmup)
        .toList();

    debugPrint('STEP ✓ with 0 reps does not switch it on');
    await h.waitFor(find.byKey(ValueKey('set-${hammerSets[0].id}')));
    await openCell(h, hammerSets[0], 'reps');
    await typeOnKeypad(h, '0');
    await checkSet(h, hammerSets[0]);
    if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    expect((await setRow(h, hammerSets[0].id)).reps, 0);
    expect((await policy()).isOn(hammer.exerciseId), isFalse, reason: 'an empty set never switches anything on');
    // Un-tick it so the next ✓ is a real one.
    await h.waitFor(find.byKey(ValueKey('set-${hammerSets[0].id}')));
    await h.tap(find.descendant(of: find.byKey(ValueKey('set-${hammerSets[0].id}')), matching: find.byTooltip('Mark not done')));

    debugPrint('STEP ✓ on a real working set switches it on (automatic)');
    await h.waitFor(find.byKey(ValueKey('set-${hammerSets[0].id}')));
    await openCell(h, hammerSets[0], 'reps');
    await typeOnKeypad(h, '10');
    await checkSet(h, hammerSets[0]);
    if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    expect((await setRow(h, hammerSets[0].id)).completed, isTrue);
    expect((await policy()).sourceOf(hammer.exerciseId), RankSource.auto);

    debugPrint('STEP a routine exercise switched off by hand stays off after its sets are done');
    final flyExId = (await tester.runAsync(() => (db.select(db.sessionExercises)..where((t) => t.id.equals(fly.first.sessionExerciseId))).getSingle()))!.exerciseId;
    await tester.runAsync(() => RankExclusions(db).set(flyExId, excluded: true));
    expect((await policy()).isOn(flyExId), isFalse);
    await h.scrollToTop();
    await checkSet(h, fly[0]);
    if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    expect((await setRow(h, fly[0].id)).completed, isTrue);
    expect((await policy()).sourceOf(flyExId), RankSource.manualOff, reason: 'auto-enable never overrides a manual off');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
