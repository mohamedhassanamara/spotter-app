import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openFromLibrary(AppHarness h, WidgetTester tester, String query, String name) async {
    if (find.byType(TextField).evaluate().isEmpty) await h.goTab(Icons.menu_book_outlined);
    await h.waitFor(find.byType(TextField), scroll: false);
    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, query);
    await h.settle(8);
    await h.tap(find.text(name).last);
    await h.waitFor(find.byKey(const ValueKey('exercise-hero')), scroll: false, reason: 'exercise page');
  }

  testWidgets('Exercise page: About · Rank · Stats · History; demo, How to log, muscles, tiles, equipment, instructions', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    debugPrint('STEP About: demo hero, Jeff thumbnail, How to log? first');
    await openFromLibrary(h, tester, 'leverage chest press', 'Leverage Chest Press');
    for (final t in ['tab-about', 'tab-rank', 'tab-stats', 'tab-history']) {
      expect(find.byKey(ValueKey(t)), findsOneWidget, reason: t);
    }
    await h.waitFor(find.byKey(const ValueKey('jeff-video-card')), scroll: false, reason: 'program exercise: Jeff thumbnail on the demo');
    expect(find.byKey(const ValueKey('how-to-log')), findsOneWidget);
    await h.shot('exercise-about-top');

    debugPrint('STEP How to log? (plate-loaded leverage machine → both sides)');
    await h.tap(find.byKey(const ValueKey('how-to-log')));
    await h.waitFor(find.byKey(const ValueKey('log-guide-headline')), scroll: false);
    expect(find.text('Log total plates on both sides'), findsOneWidget);
    expect(find.textContaining('not counted'), findsWidgets);
    await h.shot('exercise-how-to-log');
    await tester.tapAt(const Offset(200, 60));
    await h.settle(8);

    debugPrint('STEP muscles worked: front and back figures with a legend, then the primary tile opens the muscle rank sheet');
    await h.waitFor(find.byKey(const ValueKey('exercise-body-front')), reason: 'front figure');
    expect(find.byKey(const ValueKey('exercise-body-back')), findsOneWidget);
    expect(find.text('Primary'), findsWidgets);
    expect(find.text('Secondary'), findsWidgets);
    await h.scrollToTop();
    await h.waitFor(find.byKey(const ValueKey('exercise-body-front')));
    await h.waitFor(find.text('PRIMARY MUSCLE'));
    final tiles = find.byWidgetPredicate((w) => w.key is ValueKey && (w.key! as ValueKey).value.toString().startsWith('muscle-tile-'));
    await h.waitFor(tiles, reason: 'muscle tiles');
    await h.shot('exercise-about-muscles');
    await tester.tap(tiles.first);
    await h.settle(10);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget, reason: "the muscle's rank sheet");
    await tester.tapAt(const Offset(200, 60));
    await h.settle(8);

    debugPrint('STEP equipment tiles and numbered instructions');
    await h.waitFor(find.text('EQUIPMENT'));
    await h.waitFor(find.text('INSTRUCTIONS'));
    await h.shot('exercise-about-equipment');
    await h.shot('exercise-about-bottom');

    debugPrint('STEP Rank, Stats and History tabs');
    await h.scrollToTop();
    await h.tap(find.byKey(const ValueKey('tab-rank')));
    await h.waitFor(find.byKey(const ValueKey('count-toward-ranks')), scroll: false);
    expect(find.byKey(const ValueKey('rank-card')).evaluate().isNotEmpty || find.byKey(const ValueKey('rank-empty')).evaluate().isNotEmpty, isTrue);
    await h.shot('exercise-rank-tab');
    await h.tap(find.byKey(const ValueKey('tab-stats')));
    await h.waitFor(find.text('No history yet'), scroll: false, reason: 'fresh install: nothing logged');
    await h.tap(find.byKey(const ValueKey('tab-history')));
    await h.waitFor(find.text('No history yet'), scroll: false);
    await tester.pageBack();
    await h.settle(8);

    debugPrint('STEP dumbbell exercise: one dumbbell; stack exercise: stack weight');
    await openFromLibrary(h, tester, 'one-arm dumbbell row', 'One-Arm Dumbbell Row');
    await h.tap(find.byKey(const ValueKey('how-to-log')));
    await h.waitFor(find.text('Log the weight of ONE dumbbell'), scroll: false);
    await tester.tapAt(const Offset(200, 60));
    await h.settle(8);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
