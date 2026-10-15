import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/live_activity/live_activity_service.dart';

import 'harness.dart';
import 'logger_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Live Activity: ✓ starts it, Skip ends it, the next ✓ restarts it, Finish removes it (native ActivityKit)', (tester) async {
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
    final sets = await activeSets(h);
    final chest = sets['Chest Press']!;
    expect(await active(), 0);

    debugPrint('STEP ✓ on a working set: the rest starts and so does the Live Activity');
    await checkSet(h, chest[0]);
    await h.waitFor(find.textContaining('REST '), scroll: false, reason: 'rest running');
    await h.settle(6);
    expect(await active(), 1, reason: 'native Live Activity running');

    debugPrint('STEP the next ✓ replaces it (still one)');
    await checkSet(h, chest[1]);
    await h.settle(6);
    expect(await active(), 1);

    debugPrint('STEP Skip in the rest sheet ends it');
    await h.tap(find.byKey(const ValueKey('workout-clock')));
    await h.waitFor(find.text('Skip'), scroll: false);
    await h.tap(find.text('Skip'));
    await h.settle(6);
    expect(await active(), 0);

    debugPrint('STEP a new rest, then Finish removes it');
    await checkSet(h, chest[2]);
    await h.settle(6);
    expect(await active(), 1);
    await h.scrollToTop();
    await h.tap(find.text('Finish'));
    if (find.text('Finish workout?').evaluate().isNotEmpty) {
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
    }
    await h.waitFor(find.text('WORKOUT COMPLETE'), timeout: const Duration(seconds: 30), reason: 'summary');
    expect(await active(), 0);
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
