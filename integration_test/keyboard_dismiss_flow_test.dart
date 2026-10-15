import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';
import 'logger_helpers.dart';

bool get _textFocused => FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null ||
    FocusManager.instance.primaryFocus?.context?.widget is EditableText;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Keyboard: tap outside the field, scroll, and tapping outside the set table all put it away', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    debugPrint('STEP Library search: tap the field, the keyboard (focus) is there');
    await h.goTab(Icons.menu_book_outlined);
    final search = find.byType(TextField).first;
    await h.waitFor(search, scroll: false);
    await tester.tap(search);
    await h.settle(4);
    expect(_textFocused, isTrue, reason: 'the field has the focus');
    await tester.enterText(search, 'bench');
    await h.settle(4);

    debugPrint('STEP tapping inside the field (its icon) keeps it; tapping the page title away from it drops it');
    await tester.tapAt(tester.getCenter(search) + const Offset(40, 0));
    await h.settle(2);
    expect(_textFocused, isTrue);
    await tester.tapAt(tester.getTopLeft(find.byType(Scaffold).first) + const Offset(200, 100));
    await h.settle(3);
    expect(_textFocused, isFalse, reason: 'tap outside the field dismissed the keyboard');

    debugPrint('STEP focus again, then drag the results list: dismiss on drag');
    await tester.tap(search);
    await h.settle(4);
    expect(_textFocused, isTrue);
    final lists = find.byType(ListView);
    await tester.drag(lists.last, const Offset(0, -250), warnIfMissed: false);
    await h.settle(4);
    expect(_textFocused, isFalse, reason: 'scrolling the list dismissed the keyboard');

    debugPrint('STEP tapping a result (a button-like tile) also drops it');
    await tester.tap(search);
    await h.settle(3);
    expect(_textFocused, isTrue);
    await tester.tap(find.byIcon(Icons.star_rounded).first, warnIfMissed: false);
    await h.settle(3);
    expect(_textFocused, isFalse);
    await h.shot('keyboard-dismissed-library');

    debugPrint('STEP workout keypad: a tap outside the set table closes it, a tap inside does not');
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    final sets = await activeSets(h);
    await openCell(h, sets['Chest Press']![0], 'kg');
    expect(find.byKey(const ValueKey('workout-keypad')), findsOneWidget);
    await openCell(h, sets['Chest Press']![1], 'reps'); // another cell: still the keypad
    expect(find.byKey(const ValueKey('workout-keypad')), findsOneWidget);
    await tester.tapAt(const Offset(3, 300)); // the page margin, outside every table
    await h.settle(5);
    expect(find.byKey(const ValueKey('workout-keypad')), findsNothing, reason: 'tap outside the set table closed the keypad');
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
