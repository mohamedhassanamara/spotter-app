import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/widgets/game_ui.dart';

import 'harness.dart';

Finder _card(String exerciseName) => find.ancestor(of: find.text(exerciseName), matching: find.byType(GameCard)).first;

Finder _inCard(String exerciseName, Finder f) => find.descendant(of: _card(exerciseName), matching: f);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Upper: start from Train, warm-up + working sets incl. 1×20, steppers, add/remove set, '
      'replace via substitution, background/resume, cold restart, finish, summary, history, next routine from Home',
      (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    debugPrint('STEP Train → Upper → Start.');
    // Train → Upper → Start.
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Upper'), reason: 'Upper routine on Train');
    await h.tap(find.text('Start'));
    await h.waitFor(find.text('Chest Press'), reason: 'workout opened with my names');
    expect(find.text('Finish'), findsOneWidget);

    debugPrint('STEP Chest Press: 2 × 4–6 then 1 × 20 (fresh install → calibratio');
    // Chest Press: 2 × 4–6 then 1 × 20 (fresh install → calibration targets).
    await h.waitFor(_inCard('Chest Press', find.textContaining('× 20')), reason: '1×20 higher-rep target');

    debugPrint('STEP Add a warm-up and complete it.');
    // Add a warm-up and complete it.
    await h.tap(_inCard('Chest Press', find.text('Warm-up')));
    await h.waitFor(_inCard('Chest Press', find.text('W')), reason: 'warm-up row');
    await h.tap(_inCard('Chest Press', find.byTooltip('Complete set')));

    debugPrint('STEP Stepper: +1 increment on the first working sets weight, the');
    // Stepper: +1 increment on the first working set's weight, then complete all 3 working sets.
    final firstWeight = _inCard('Chest Press', find.byType(StepperBox)).first;
    await h.tap(find.descendant(of: firstWeight, matching: find.byIcon(Icons.add_rounded)));
    for (var i = 0; i < 3; i++) {
      await h.tap(_inCard('Chest Press', find.byTooltip('Complete set')));
      // The rest timer starts after a working set; skip it.
      if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    }
    expect(_inCard('Chest Press', find.byTooltip('Complete set')), findsNothing, reason: 'all Chest Press sets done');

    debugPrint('STEP Add a set to Straight Arm Pulldown, then delete it from the ');
    // Add a set to Straight Arm Pulldown, then delete it from the set editor.
    final before = _inCard('Straight Arm Pulldown', find.byTooltip('Complete set')).evaluate().length;
    await h.tap(_inCard('Straight Arm Pulldown', find.text('Set')));
    expect(_inCard('Straight Arm Pulldown', find.byTooltip('Complete set')).evaluate().length, before + 1);
    await h.longPress(_inCard('Straight Arm Pulldown', find.textContaining('TARGET')).last);
    await h.tap(find.text('Delete'));
    expect(_inCard('Straight Arm Pulldown', find.byTooltip('Complete set')).evaluate().length, before);

    debugPrint('STEP Replace Machine Chest Fly via the programs substitutions (D');
    // Replace Machine Chest Fly via the program's substitutions (DB Flye).
    await h.tap(_inCard('Machine Chest Fly', find.byIcon(Icons.more_vert_rounded)));
    await h.tap(find.text('Replace exercise'));
    await h.waitFor(find.text('FROM THE PROGRAM'));
    await h.tap(find.text('DB Flye'));
    await h.waitFor(find.text('Dumbbell Flyes'), reason: 'replaced exercise card');
    expect(find.text('Machine Chest Fly'), findsNothing);

    debugPrint('STEP Background mid-workout and resume.');
    // Background mid-workout and resume.
    // While paused the engine schedules no frames, so wait in real time without pumping.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    // Still on the workout (the list is scrolled down to the replaced card), sets intact.
    expect(find.text('Dumbbell Flyes'), findsOneWidget);
    final done = await tester.runAsync(() => h.db!.select(h.db!.workoutSets).get());
    expect(done!.where((s) => s.completed).length, 4, reason: '1 warm-up + 3 Chest Press sets');

    debugPrint('STEP Cold restart: the workout survives and resumes from Home.');
    // Cold restart: the workout survives and resumes from Home.
    await h.pumpApp();
    await h.tap(find.text('Resume Upper'));
    await h.waitFor(find.text('Chest Press'));
    expect(_inCard('Chest Press', find.byTooltip('Complete set')), findsNothing, reason: 'logged sets survived the restart');

    debugPrint('STEP Finish → summary → Done.');
    // Finish → summary → Done.
    await h.tap(find.text('Finish'));
    if (find.text('Finish workout?').evaluate().isNotEmpty) {
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
    }
    await h.waitFor(find.text('WORKOUT COMPLETE'), timeout: const Duration(seconds: 30), reason: 'summary');
    await h.tap(find.text('Done'));

    debugPrint('STEP History shows the session.');
    // History shows the session.
    await h.goTab(Icons.insights_outlined);
    await h.tap(find.text('History'));
    await h.waitFor(find.textContaining('Upper'), reason: 'session in history');
    await h.tap(find.textContaining('Upper').last);
    await h.waitFor(find.text('Chest Press'), reason: 'session detail uses my names');
    await tester.pageBack();
    await h.settle();

    debugPrint('STEP Home → start the next routine (Lower).');
    // Home → start the next routine (Lower).
    await h.goTab(Icons.home_outlined);
    await h.tap(find.text('Start Lower'));
    await h.waitFor(find.text('Lying Leg Curl'), reason: 'Lower started from Home');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Pull: Assisted Pull-Ups log assistance as negative load', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Pull'));
    // Routine cards are Upper, Lower, Push, Pull, Arms: Pull's Start is the 4th.
    await h.tap(find.text('Start').at(3));
    await h.waitFor(find.text('Assisted Pull-Ups'));

    debugPrint('STEP Calibration starts with half of bodyweight as assistance: −4');
    // Calibration starts with half of bodyweight as assistance: −40 kg at 80 kg.
    await h.waitFor(_inCard('Assisted Pull-Ups', find.text('-40')), reason: 'negative assistance');
    final weight = _inCard('Assisted Pull-Ups', find.byType(StepperBox)).first;
    await h.tap(find.descendant(of: weight, matching: find.byIcon(Icons.add_rounded)));
    await h.waitFor(_inCard('Assisted Pull-Ups', find.text('-37.5')), reason: '+ means less assistance');
    for (var i = 0; i < 3; i++) {
      await h.tap(_inCard('Assisted Pull-Ups', find.byTooltip('Complete set')));
      if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    }

    await h.tap(find.text('Finish'));
    if (find.text('Finish workout?').evaluate().isNotEmpty) {
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
    }
    await h.waitFor(find.text('WORKOUT COMPLETE'), timeout: const Duration(seconds: 30));
    final sets = await tester.runAsync(() => h.db!.select(h.db!.workoutSets).get());
    expect(sets!.where((s) => s.completed).every((s) => s.weight < 0), isTrue, reason: 'assistance stored as negative load');
    await h.tap(find.text('Done'));

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
