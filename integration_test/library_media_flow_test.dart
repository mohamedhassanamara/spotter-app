import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/features/tutorials/data/edb_v2/edb_client.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Library: merged free sources, static thumbnails, Jeff\'s video for program exercises, '
      'GIF/photos + credits otherwise, zero ExerciseDB V2 calls', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    debugPrint('STEP library size after the merge');
    await h.goTab(Icons.menu_book_outlined);
    final all = await tester.runAsync(() => h.db!.select(h.db!.exercises).get());
    expect(all!.length, greaterThan(2300));
    await h.waitFor(find.textContaining('Search ${all.length}'), reason: 'search hint counts the merged library', scroll: false);

    debugPrint('STEP program exercise → Jeff Nippard video');
    await tester.enterText(find.byType(TextField).first, 'Leverage Chest Press');
    await h.settle(6);
    await h.tap(find.text('Leverage Chest Press').last);
    await h.waitFor(find.byKey(const ValueKey('program-video')), reason: 'embedded program video', scroll: false);
    expect(find.textContaining('Jeff Nippard · Machine Chest Press'), findsOneWidget);
    await tester.pageBack();
    await h.settle();

    debugPrint('STEP wger exercise → Demo tab, credits with licence');
    await tester.enterText(find.byType(TextField).first, 'Kettlebell Swing');
    await h.settle(6);
    await h.tap(find.text('2 Handed Kettlebell Swing'));
    await h.waitFor(find.byKey(const ValueKey('exercise-hero')), reason: 'no program video: GIF or generated demo', scroll: false);
    await h.waitFor(find.byKey(const ValueKey('exercise-credit')));
    expect(find.textContaining('wger.de'), findsOneWidget);
    expect(find.byKey(const ValueKey('program-video')), findsNothing);
    await tester.pageBack();
    await h.settle();

    debugPrint('STEP no ExerciseDB V2 traffic while it is off');
    expect(await tester.runAsync(() => h.db!.getSetting(EdbBudgetStore.budgetKey)), isNull);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
