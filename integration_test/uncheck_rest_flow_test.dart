import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/live_activity/live_activity_service.dart';

import 'harness.dart';
import 'logger_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Unchecking a set cancels the rest it started (timer, Live Activity); another set\'s rest is left alone', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final native = ChannelLiveActivityService();
    Future<int> active() async => (await tester.runAsync(native.activeCount))!;
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    final sets = (await activeSets(h))['Chest Press']!;
    Finder untick(int id) => find.descendant(of: find.byKey(ValueKey('set-$id')), matching: find.byTooltip('Mark not done'));

    debugPrint('STEP ✓ starts a rest and a Live Activity; un-ticking that set cancels the rest (the activity goes back to the workout view)');
    await checkSet(h, sets[0]);
    await h.waitFor(find.textContaining('REST '), scroll: false, reason: 'rest running');
    await h.settle(6);
    expect(await active(), 1);
    await h.tap(untick(sets[0].id));
    await h.settle(6);
    expect(find.textContaining('REST '), findsNothing, reason: 'the header is back to the workout clock');
    expect(await active(), 1, reason: 'the workout\'s Live Activity stays, back in its working view (no rest)');
    expect((await setRow(h, sets[0].id)).completed, isFalse);

    debugPrint('STEP two sets done: un-ticking the EARLIER one leaves the later set\'s rest running');
    await checkSet(h, sets[0]);
    await h.settle(3);
    await checkSet(h, sets[1]);
    await h.waitFor(find.textContaining('REST '), scroll: false);
    await h.settle(4);
    await h.tap(untick(sets[0].id));
    await h.settle(4);
    expect(find.textContaining('REST '), findsOneWidget, reason: 'set 2\'s rest is still running');
    expect(await active(), 1);

    debugPrint('STEP un-ticking set 2 itself cancels it');
    await h.tap(untick(sets[1].id));
    await h.settle(5);
    expect(find.textContaining('REST '), findsNothing);
    expect(await active(), 1, reason: 'still the workout\'s activity');
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
