import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';
import 'logger_helpers.dart';
import 'streak_finish_flow_test.dart' show finishWorkout, onlyWorkout;

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

  testWidgets('After a workout: Congratulations → Rank → Streak → Home; Skip leaves at any point; screens with nothing to show are not shown', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await tester.runAsync(() => onlyWorkout(h.db!, 1)); // trained yesterday: today's workout grows the streak
    await h.pumpApp();

    debugPrint('STEP finish: Congratulations first, with no streak or rank block on it');
    await startUpperAndTick(h);
    await finishWorkout(h);
    expect(find.text('WORKOUT COMPLETE'), findsOneWidget);
    expect(find.byKey(const ValueKey('streak-celebration')), findsNothing, reason: 'the streak has its own screen now');
    expect(find.byKey(const ValueKey('after-skip')), findsOneWidget);
    await h.shot('after-1-congratulations');

    debugPrint('STEP Continue → Rank (when a rank moved) → Streak');
    await h.tap(find.byKey(const ValueKey('after-continue')));
    await h.settle(10);
    if (find.byKey(const ValueKey('rank-sequence')).evaluate().isNotEmpty) {
      await h.shot('after-2-rank');
      await tester.tap(find.byKey(const ValueKey('rank-sequence')));
      await h.settle(8);
      if (find.text('RANK UP').evaluate().isNotEmpty) {
        await tester.tapAt(const Offset(200, 400));
        await h.settle(6);
      }
    }
    await h.waitFor(find.byKey(const ValueKey('streak-celebration')), scroll: false, reason: 'the Streak screen is last');
    await h.settle(10);
    expect(find.text('2-day streak'), findsOneWidget);
    await h.shot('after-3-streak');
    await h.tap(find.byKey(const ValueKey('after-continue')));
    await h.waitFor(find.text('OVERALL RANK'), scroll: false, reason: 'Home after the last screen');

    debugPrint('STEP second workout the same day: no streak screen; Skip on Congratulations goes straight Home');
    await startUpperAndTick(h, start: 1);
    await finishWorkout(h);
    if (find.byKey(const ValueKey('after-skip')).evaluate().isNotEmpty) {
      expect(find.byKey(const ValueKey('after-continue')), findsOneWidget);
      await h.tap(find.byKey(const ValueKey('after-skip')));
    }
    await h.waitFor(find.text('OVERALL RANK'), scroll: false, reason: 'Skip went straight Home');
    expect(find.byKey(const ValueKey('streak-celebration')), findsNothing);

    debugPrint('STEP skip from the Streak screen too');
    await tester.runAsync(() => onlyWorkout(h.db!, 1));
    await h.pumpApp();
    await startUpperAndTick(h, start: 2);
    await finishWorkout(h);
    await h.tap(find.byKey(const ValueKey('after-continue')));
    await h.settle(10);
    if (find.byKey(const ValueKey('rank-sequence')).evaluate().isNotEmpty) {
      await h.tap(find.byKey(const ValueKey('after-skip')));
    } else if (find.byKey(const ValueKey('streak-celebration')).evaluate().isNotEmpty) {
      await h.tap(find.byKey(const ValueKey('after-skip')));
    }
    await h.waitFor(find.text('OVERALL RANK'), scroll: false, reason: 'Skip from a later screen goes Home');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
