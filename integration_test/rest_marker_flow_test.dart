import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';
import 'logger_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Rest marker between sets: the actual rest taken, from ✓ to ✓ or until the timer was skipped', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    final sets = (await activeSets(h))['Chest Press']!;

    Future<void> realWait(int seconds) => tester.runAsync(() => Future<void>.delayed(Duration(seconds: seconds)));

    debugPrint('STEP set 1 ✓: no marker yet (no previous set)');
    await checkSet(h, sets[0]);
    await h.settle(4);
    expect(find.byKey(ValueKey('rest-marker-${sets[0].id}')), findsNothing);
    expect(find.byKey(ValueKey('rest-marker-${sets[1].id}')), findsNothing, reason: 'set 2 is not done yet');

    debugPrint('STEP the rest runs; skipping it ends the rest there');
    await realWait(3);
    await h.tap(find.byKey(const ValueKey('workout-clock')));
    await h.waitFor(find.text('Skip'), scroll: false);
    await h.tap(find.text('Skip'));
    await h.settle(3);

    debugPrint('STEP a long while later set 2 ✓: the marker shows the rest until the skip, not until this ✓');
    await realWait(7);
    await checkSet(h, sets[1]);
    await h.settle(4);
    await h.waitFor(find.byKey(ValueKey('rest-marker-${sets[1].id}')), scroll: false, reason: 'rest marker between set 1 and 2');
    final s1 = await setRow(h, sets[0].id), s2 = await setRow(h, sets[1].id);
    final gap = s2.completedAt!.difference(s1.completedAt!).inSeconds;
    expect(s2.restSeconds, isNotNull);
    expect(s2.restSeconds!, lessThan(gap - 4), reason: 'skipped ~7 s before the ✓: rest $gap s apart, stored ${s2.restSeconds}');
    expect(s2.restSeconds!, greaterThanOrEqualTo(2));
    final label = find.descendant(of: find.byKey(ValueKey('rest-marker-${sets[1].id}')), matching: find.byType(Text));
    expect((label.evaluate().first.widget as Text).data, matches(RegExp(r'^\d+:\d{2}$')));
    await h.shot('rest-marker');

    debugPrint('STEP set 3 ✓ with the timer left running: ✓ to ✓');
    await realWait(3);
    await checkSet(h, sets[2]);
    await h.settle(4);
    final s3 = await setRow(h, sets[2].id);
    expect(s3.restSeconds, s3.completedAt!.difference((await setRow(h, sets[1].id)).completedAt!).inSeconds);
    await h.waitFor(find.byKey(ValueKey('rest-marker-${sets[2].id}')), scroll: false);

    debugPrint('STEP un-ticking a set removes its marker');
    await h.tap(find.descendant(of: find.byKey(ValueKey('set-${sets[2].id}')), matching: find.byTooltip('Mark not done')));
    await h.settle(3);
    expect(find.byKey(ValueKey('rest-marker-${sets[2].id}')), findsNothing);
    expect((await setRow(h, sets[2].id)).restSeconds, isNull);
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
