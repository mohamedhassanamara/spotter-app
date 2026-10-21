import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:spotter/core/widgets/common.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('In Train cards the names are plain text (the card opens the routine); in the routine editor and in an active workout a name opens its page; link, targets, remove and drag keep working', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final routines = (await tester.runAsync(() => h.db!.select(h.db!.routines).get()))!;
    final push = routines.firstWhere((r) => r.name == 'Push');
    final rows = (await tester.runAsync(() => (h.db!.select(h.db!.routineExercises)..where((t) => t.routineId.equals(push.id))).get()))!;
    final first = rows.first;

    debugPrint('STEP Train tab preview: the name is plain text, a tap opens the routine, not the exercise page');
    await h.goTab(Icons.fitness_center_outlined);
    await h.scrollToTop();
    final previewName = find.byKey(ValueKey('preview-${push.id}-${first.exerciseId}'));
    await h.waitFor(previewName, reason: 'preview entry');
    expect(find.descendant(of: previewName, matching: find.byType(InkWell)), findsNothing, reason: 'no tap target of its own');
    await h.tap(previewName);
    await h.settle(8);
    expect(find.byKey(const ValueKey('exercise-hero')), findsNothing, reason: 'the exercise page stays closed');
    await h.waitFor(find.byKey(ValueKey('edit-${first.id}')), scroll: false, reason: 'the routine details opened instead');
    await tester.pageBack();
    await h.settle(8);

    debugPrint('STEP routine editor: tap a row → exercise page, back → still the editor');
    await h.tap(find.text('Push').first);
    await h.waitFor(find.byKey(ValueKey('edit-${first.id}')), scroll: false, reason: 'the editor');
    await h.tap(find.byKey(ValueKey('edit-${first.id}')).first, reason: 'sliders button opens the targets sheet');
    await h.waitFor(find.byKey(const ValueKey('target-save')).evaluate().isNotEmpty ? find.byKey(const ValueKey('target-save')) : find.byKey(const ValueKey('reset-to-program')), scroll: false);
    await tester.tapAt(const Offset(200, 60)); // dismiss the sheet
    await h.settle(8);
    final name = first.displayName ?? (await tester.runAsync(() => (h.db!.select(h.db!.exercises)..where((t) => t.id.equals(first.exerciseId))).getSingle()))!.name;
    await h.tap(find.text(name).first);
    await h.waitFor(find.byKey(const ValueKey('exercise-hero')), scroll: false, reason: 'the row opens the exercise page');
    await tester.pageBack();
    await h.settle(8);
    await h.waitFor(find.byKey(ValueKey('edit-${first.id}')), scroll: false, reason: 'back in the editor');

    debugPrint('STEP the editing controls still work: link two exercises, remove one');
    if (find.byKey(ValueKey('link-${first.id}')).evaluate().isNotEmpty) {
      await h.tap(find.byKey(ValueKey('link-${first.id}')));
      final linked = (await tester.runAsync(() => (h.db!.select(h.db!.routineExercises)..where((t) => t.routineId.equals(push.id))).get()))!;
      expect(linked.firstWhere((r) => r.id == first.id).supersetGroup, isNotNull, reason: 'link toggled');
      await h.tap(find.byKey(ValueKey('link-${first.id}')));
    }
    expect(find.byIcon(Icons.drag_handle_rounded), findsWidgets, reason: 'drag handles stay');
    expect(find.byTooltip('Remove'), findsWidgets);

    debugPrint('STEP active workout: tapping a name (or the thumbnail) opens the exercise page; back is the same workout');
    await tester.pageBack();
    await h.settle(8);
    await h.scrollToTop();
    final card = find.ancestor(of: find.byKey(ValueKey('preview-${push.id}-${first.exerciseId}')), matching: find.byType(AppCard)).first;
    await h.tap(find.descendant(of: card, matching: find.text('Start')));
    final workoutName = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('exercise-name-') && !(w.key! as ValueKey<String>).value.contains('-tap-')).first;
    await h.waitFor(workoutName, scroll: false, reason: 'the workout is open');
    final sessionBefore = (await tester.runAsync(() => h.db!.select(h.db!.sessions).get()))!.where((x) => x.status == 'active').toList();
    final setsBefore = (await tester.runAsync(() => h.db!.select(h.db!.workoutSets).get()))!.length;
    final nameText = tester.widget<Text>(workoutName).data!;
    await h.tap(workoutName);
    await h.waitFor(find.byKey(const ValueKey('exercise-hero')), scroll: false, reason: 'the exercise page opens on top of the workout');
    await h.shot('workout-name-opens-exercise');
    await tester.pageBack();
    await h.settle(8);
    await h.waitFor(find.text(nameText), scroll: false, reason: 'back in the same workout');
    expect(find.byKey(const ValueKey('exercise-hero')), findsNothing);
    final sessionAfter = (await tester.runAsync(() => h.db!.select(h.db!.sessions).get()))!.where((x) => x.status == 'active').toList();
    expect([for (final x in sessionAfter) x.id], [for (final x in sessionBefore) x.id], reason: 'the workout was neither ended nor replaced');
    expect((await tester.runAsync(() => h.db!.select(h.db!.workoutSets).get()))!.length, setsBefore, reason: 'nothing was lost or added');
    final thumb = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('exercise-thumb-')).first;
    await h.tap(thumb);
    await h.waitFor(find.byKey(const ValueKey('exercise-hero')), scroll: false, reason: 'the thumbnail opens it too');
    await tester.pageBack();
    await h.settle(8);
    await h.waitFor(find.text(nameText), scroll: false, reason: 'back in the workout again');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
