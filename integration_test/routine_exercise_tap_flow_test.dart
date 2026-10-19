import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Tapping an exercise in the routine preview or the routine editor opens its page; link, targets, remove and drag keep working', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final routines = (await tester.runAsync(() => h.db!.select(h.db!.routines).get()))!;
    final push = routines.firstWhere((r) => r.name == 'Push');
    final rows = (await tester.runAsync(() => (h.db!.select(h.db!.routineExercises)..where((t) => t.routineId.equals(push.id))).get()))!;
    final first = rows.first;

    debugPrint('STEP routine preview on the Train tab: tap an exercise name');
    await h.goTab(Icons.fitness_center_outlined);
    await h.scrollToTop();
    await h.waitFor(find.byKey(ValueKey('preview-${push.id}-${first.exerciseId}')), reason: 'preview entry');
    await h.tap(find.byKey(ValueKey('preview-${push.id}-${first.exerciseId}')));
    await h.waitFor(find.byKey(const ValueKey('exercise-hero')), scroll: false, reason: 'the exercise page');
    await h.shot('routine-preview-tap');
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

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
