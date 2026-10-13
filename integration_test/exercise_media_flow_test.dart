import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("Fix 4: exercise page shows the 3D GIF hero AND Jeff's video card; the (i) sheet loops the GIF "
      "with a Watch Jeff's demo button", (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    for (var i = 0; i < 60; i++) {
      if ((await tester.runAsync(() => h.db!.select(h.db!.mediaMatches).get()))!.length > 2000) break;
      await h.settle(5);
    }

    debugPrint('STEP program exercise: GIF on top, Jeff card below, then Steps');
    await h.goTab(Icons.menu_book_outlined);
    await tester.enterText(find.byType(TextField).first, 'Leverage Chest Press');
    await h.settle(6);
    await h.tap(find.text('Leverage Chest Press').last);
    await h.waitFor(find.byKey(const ValueKey('exercise-hero')), scroll: false);
    await h.waitFor(find.textContaining('3D demo: ExerciseDB'), timeout: const Duration(seconds: 30), reason: 'the GIF is the hero', scroll: false);
    await h.waitFor(find.byKey(const ValueKey('jeff-video-card')), reason: 'Jeff card as well');
    expect(find.byKey(const ValueKey('program-video')), findsOneWidget);
    final hero = tester.getRect(find.byKey(const ValueKey('exercise-hero')));
    final card = tester.getRect(find.byKey(const ValueKey('jeff-video-card')));
    expect(card.top, greaterThan(hero.top), reason: 'GIF first, video below');
    await h.scrollToTop();
    await h.settle(10);
    await h.shot('exercise-gif-and-jeff');
    await tester.pageBack();
    await h.settle();

    debugPrint('STEP non-program exercise: GIF only, no Jeff card');
    await tester.enterText(find.byType(TextField).first, 'barbell cur');
    await h.settle(6);
    await h.tap(find.text('Barbell Curl').first);
    await h.waitFor(find.textContaining('3D demo: ExerciseDB'), timeout: const Duration(seconds: 30), scroll: false);
    expect(find.byKey(const ValueKey('jeff-video-card')), findsNothing);
    await tester.pageBack();
    await h.settle();

    debugPrint("STEP in-workout (i): GIF first, then Watch Jeff's demo");
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Push'));
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.text('High-to-Low Cable Fly'));
    await h.tap(find.byKey(const ValueKey('menu-1')));
    await h.tap(find.text('How to').last);
    await h.waitFor(find.textContaining('3D demo: ExerciseDB'), timeout: const Duration(seconds: 30), reason: 'GIF in the sheet', scroll: false);
    expect(find.byKey(const ValueKey('program-video')), findsNothing, reason: 'video only on request');
    await h.tap(find.byKey(const ValueKey('watch-jeff')));
    await h.waitFor(find.byKey(const ValueKey('program-video')), reason: 'Jeff video in the sheet', scroll: false);
    await h.shot('info-sheet-gif-jeff');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
