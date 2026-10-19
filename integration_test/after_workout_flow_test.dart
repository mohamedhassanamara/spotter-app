import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';
import 'logger_helpers.dart';
import 'streak_finish_flow_test.dart' show onlyWorkout;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> startUpperAndTick(AppHarness h, {int start = 0}) async {
    await h.goTab(Icons.fitness_center_outlined);
    await h.scrollToTop();
    await h.waitFor(find.text('Start'));
    await h.tap(find.text('Start').at(start));
    await h.waitFor(find.text('Finish'), reason: 'workout opened');
    final sets = await activeSets(h);
    await checkSet(h, sets.values.first.first);
    await h.settle(3);
  }

  Future<void> tapFinish(AppHarness h) async {
    await h.scrollToTop();
    await h.tap(find.text('Finish'));
    if (find.text('Finish workout?').evaluate().isNotEmpty) {
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
    }
    await h.settle(6);
    if (find.text('Update routine?').evaluate().isNotEmpty) await h.tap(find.byKey(const ValueKey('keep-routine')));
  }

  testWidgets('After a workout: loader → Congratulations → Rank (overall first, then lifts, Continue only at the end) → Streak (flame) → Home; Skip everywhere',
      (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await tester.runAsync(() => onlyWorkout(h.db!, 1)); // trained yesterday: today's workout grows the streak
    await h.pumpApp();

    debugPrint('STEP Finish: the "Calculating your results…" loader first');
    await startUpperAndTick(h);
    await h.scrollToTop();
    await tester.tap(find.text('Finish'));
    await tester.pump(const Duration(milliseconds: 400));
    if (find.text('Finish workout?').evaluate().isNotEmpty) {
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
      await tester.pump(const Duration(milliseconds: 400));
    }
    if (find.text('Update routine?').evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('keep-routine')));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.byKey(const ValueKey('calculating-results')), findsOneWidget, reason: 'the loader comes right after Finish');
    expect(find.textContaining('Calculating your results'), findsOneWidget);
    expect(find.text('WORKOUT COMPLETE'), findsNothing, reason: 'nothing else before the loader is done');
    await h.shot('after-0-loader');

    debugPrint('STEP Congratulations: duration, effort, volume, PRs, XP');
    await h.waitForSummary(reason: 'Congratulations after the loader');
    for (final k in ['stat-duration', 'stat-effort', 'stat-volume', 'stat-prs']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    expect(find.textContaining(' XP'), findsWidgets);
    expect(find.byKey(const ValueKey('streak-celebration')), findsNothing);
    await h.shot('after-1-congratulations');

    debugPrint('STEP Continue → Rank: nothing auto-advances, Continue only after the animations');
    await h.tap(find.byKey(const ValueKey('after-continue')));
    await tester.pump(const Duration(seconds: 1)); // the page transition
    await h.settle(4);
    if (find.text('RANK UP').evaluate().isNotEmpty) {
      await h.shot('after-2a-rank-up');
      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(seconds: 1));
      await h.settle(2);
    }
    if (find.byKey(const ValueKey('rank-sequence')).evaluate().isNotEmpty) {
      await h.shot('after-2b-rank');
      await tester.tap(find.byKey(const ValueKey('rank-sequence'))); // fast-forward
      await h.settle(6);
      expect(find.byKey(const ValueKey('rank-sequence')), findsOneWidget, reason: 'a tap does not leave');
      await h.tap(find.byKey(const ValueKey('after-continue')));
    }

    debugPrint('STEP Streak: the flame, then Continue → Home');
    await h.waitFor(find.byKey(const ValueKey('streak-celebration')), scroll: false, reason: 'the Streak screen');
    await tester.pump(const Duration(milliseconds: 900)); // transition done, the flame still burning
    expect(find.byKey(const ValueKey('after-continue')), findsNothing, reason: 'Continue waits for the flame');
    await h.settle(10);
    await h.shot('after-3-streak');
    await h.waitFor(find.byKey(const ValueKey('after-continue')), timeout: const Duration(seconds: 10), scroll: false, reason: 'Continue after the flame');
    expect(find.text('2-day streak'), findsOneWidget);
    await h.tap(find.byKey(const ValueKey('after-continue')));
    await h.waitFor(find.text('OVERALL RANK'), scroll: false, reason: 'Home after the last screen');

    debugPrint('STEP second workout the same day: no Streak screen; Skip on Congratulations goes straight Home');
    await startUpperAndTick(h, start: 1);
    await tapFinish(h);
    await h.waitForSummary();
    await h.tap(find.byKey(const ValueKey('after-skip')));
    await h.waitFor(find.text('OVERALL RANK'), scroll: false, reason: 'Skip went straight Home');

    debugPrint('STEP Skip from the Rank / Streak screen too');
    await tester.runAsync(() => onlyWorkout(h.db!, 1));
    await h.pumpApp();
    await startUpperAndTick(h, start: 2);
    await tapFinish(h);
    await h.waitForSummary();
    await h.tap(find.byKey(const ValueKey('after-continue')));
    await h.settle(10);
    if (find.byKey(const ValueKey('after-skip')).evaluate().isNotEmpty) {
      await h.tap(find.byKey(const ValueKey('after-skip')));
    } else {
      await tester.tapAt(const Offset(200, 400)); // the full-screen rank-up has no Skip: a tap moves on, then Skip
      await h.settle(6);
      if (find.byKey(const ValueKey('after-skip')).evaluate().isNotEmpty) await h.tap(find.byKey(const ValueKey('after-skip')));
    }
    await h.waitFor(find.text('OVERALL RANK'), scroll: false, reason: 'Skip from a later screen goes Home');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
