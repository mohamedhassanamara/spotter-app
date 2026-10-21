import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';
import 'logger_helpers.dart';

String _csv() {
  final t = DateTime.now().subtract(const Duration(days: 8));
  String two(int v) => v.toString().padLeft(2, '0');
  final d = '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
  const dur = '01 hours 00 minutes 00 seconds';
  // Chest press at 60 kg × 6 (a modest baseline), so a normal progression raises the rank.
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
      '$d,$dur,,Chest Press,0,132.3,6,0,0,,6-8\n'
      '$d,$dur,,Chest Press,1,132.3,6,0,0,,6-8\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Rank animations: the lift strip rises as a set is ticked; Finish plays the rank sequence (skippable), then the summary',
      (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '80');
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    final chest = (await activeSets(h))['Chest Press']!;
    final exId = chest.first.sessionExerciseId;
    final label = find.byKey(ValueKey('rank-strip-label-${(await tester.runAsync(() => (h.db!.select(h.db!.sessionExercises)..where((t) => t.id.equals(exId))).getSingle()))!.exerciseId}'));
    await h.waitFor(label, reason: 'rank strip on the Chest Press block');
    final gap = find.byKey(ValueKey('rank-gap-${(await tester.runAsync(() => (h.db!.select(h.db!.sessionExercises)..where((t) => t.id.equals(exId))).getSingle()))!.exerciseId}'));
    final gapBefore = tester.widget<Text>(gap).data;
    final before = tester.widget<Text>(label).data!;
    debugPrint('STEP strip before the set: $before');

    debugPrint('STEP tick the first working set at its suggested weight for 8 reps (more than last time)');
    await openCell(h, chest[0], 'reps');
    await typeOnKeypad(h, '8');
    await h.tap(find.byKey(const ValueKey('key-hide')));
    await checkSet(h, chest[0]);
    await h.settle(10);
    final after = tester.widget<Text>(label).data!;
    debugPrint('STEP strip after the set: $after');
    expect((await setRow(h, chest[0].id)).completed, isTrue);
    // The strip shows a real set that reaches the next division ("6 × 72.5 kg → Gold 2"), not an e1RM gap.
    final target = RegExp(r'^\d+ × (BW|−?[\d.]+ kg)( \(max\))? → \w+ \d$');
    expect(gapBefore, matches(target), reason: 'a concrete set before the first set');
    expect(tester.widget<Text>(gap).data, matches(target), reason: 'still a concrete set after the set raised the lift\'s rank live');
    await h.shot('rank-strip-after-set');

    debugPrint('STEP Finish: Congratulations, then the Rank screen plays (lifts first), a tap skips it');
    await h.scrollToTop();
    await h.tap(find.text('Finish'));
    if (find.text('Finish workout?').evaluate().isNotEmpty) {
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
    }
    await h.waitForSummary(reason: 'Congratulations is the first screen');
    await h.tap(find.byKey(const ValueKey('after-continue')));
    // The overall rank may have moved a division: the full-screen rank-up shows first, a tap moves on.
    await h.waitFor(find.byKey(const ValueKey('rank-sequence')), timeout: const Duration(seconds: 30), scroll: false, reason: 'the Rank screen');
    if (find.text('RANK UP').evaluate().isNotEmpty) {
      await h.shot('rank-up-overall');
      await tester.tapAt(const Offset(200, 400));
      await h.settle(6);
    }
    await h.waitFor(find.byKey(const ValueKey('gain-exercise-Chest Press')), scroll: false, reason: 'the lift animates');
    await h.shot('rank-sequence');
    await tester.tap(find.byKey(const ValueKey('rank-sequence'))); // fast-forward
    await h.waitFor(find.byKey(const ValueKey('after-continue')), scroll: false, reason: 'Continue once the animations are done');
    await h.tap(find.byKey(const ValueKey('after-continue')));
    // Then the streak (today's workout grew it) or Home.
    await h.settle(10);
    if (find.byKey(const ValueKey('streak-celebration')).evaluate().isNotEmpty) {
      await h.waitFor(find.byKey(const ValueKey('after-continue')), timeout: const Duration(seconds: 10), scroll: false);
      await h.tap(find.byKey(const ValueKey('after-continue')));
    }
    await h.waitFor(find.text('OVERALL RANK'), timeout: const Duration(seconds: 20), reason: 'back on Home', scroll: false);
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
