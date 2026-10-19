import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Motion: tabs fade in and keep their state, library rows animate in, the thumbnail flies into the exercise page and back', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    debugPrint('STEP tab switches: Library, then Train, then back to Library keeps the search');
    await h.goTab(Icons.menu_book_outlined);
    await h.waitFor(find.byType(TextField), scroll: false);
    await tester.enterText(find.byType(TextField).first, 'Leverage Chest Press');
    await h.settle(8);
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start'), reason: 'Train tab');
    expect(find.byType(TextField), findsNothing, reason: 'only the current tab is shown (the Library search is hidden)');
    await h.goTab(Icons.menu_book_outlined);
    await h.settle(10);
    expect(find.text('Leverage Chest Press'), findsWidgets, reason: 'the Library tab kept its search');

    debugPrint('STEP the row\'s thumbnail is a hero that flies into the exercise page');
    await h.tap(find.text('Leverage Chest Press').last);
    await h.settle(4); // mid-flight
    await h.waitFor(find.byKey(const ValueKey('exercise-hero')), scroll: false, reason: 'the exercise page');
    await h.shot('motion-exercise-page');
    await tester.pageBack();
    await h.settle(10);
    expect(find.text('Leverage Chest Press'), findsWidgets, reason: 'back on the library list');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
