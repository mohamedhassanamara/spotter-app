import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';

import 'harness.dart';
import 'logger_helpers.dart';

/// Only one finished workout, [daysAgo] days ago at 10:00.
Future<void> onlyWorkout(AppDatabase db, int daysAgo) async {
  await db.delete(db.workoutSets).go();
  await db.delete(db.sessionExercises).go();
  await db.delete(db.sessions).go();
  final n = DateTime.now();
  final at = DateTime(n.year, n.month, n.day - daysAgo, 10);
  final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(name: 'Upper', startedAt: at, endedAt: Value(at.add(const Duration(hours: 1))), status: const Value('active')));
  final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
        sessionId: sid, exerciseId: 'Barbell_Curl', position: 0, repMin: 8, repMax: 12, targetSets: 1, restSeconds: 90));
  await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
        sessionExerciseId: ex, position: 0, weight: const Value(30), reps: const Value(10), rpe: const Value(9), completed: const Value(true), completedAt: Value(at)));
  await (db.update(db.sessions)..where((t) => t.id.equals(sid))).write(const SessionsCompanion(status: Value('finished')));
}

Future<void> finishWorkout(AppHarness h) async {
  await h.scrollToTop();
  await h.tap(find.text('Finish'));
  if (find.text('Finish workout?').evaluate().isNotEmpty) {
    await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
  }
  await h.settle(6);
  if (find.text('Update routine?').evaluate().isNotEmpty) await h.tap(find.byKey(const ValueKey('keep-routine')));
  await h.waitFor(find.text('WORKOUT COMPLETE'), timeout: const Duration(seconds: 30), reason: 'summary');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Streak at Finish: today counts only once the workout is finished, with a celebration; a second workout the same day adds nothing',
      (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final db = h.db!;

    debugPrint('STEP trained yesterday: Home shows 1 and says today is not counted yet');
    await tester.runAsync(() => onlyWorkout(db, 1));
    await h.pumpApp();
    await h.waitFor(find.byKey(const ValueKey('streak-card')), reason: 'Home streak card');
    await h.waitFor(find.text('1-day streak'), scroll: false);
    expect(find.textContaining('today counts when you finish a workout'), findsOneWidget);

    debugPrint('STEP finish a workout: the celebration ticks 1 → 2');
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    final sets = await activeSets(h);
    await checkSet(h, sets['Chest Press']![0]);
    await h.settle(3);
    await finishWorkout(h);
    await h.waitFor(find.byKey(const ValueKey('streak-celebration')), scroll: false);
    await h.settle(10);
    expect(find.text('2-day streak'), findsOneWidget);
    await h.shot('streak-celebration');

    debugPrint('STEP back on Home: 2-day streak, trained today');
    await h.tap(find.text('Done'));
    await h.waitFor(find.text('2-day streak'), scroll: false);
    expect(find.text('Safe: trained today'), findsOneWidget);

    debugPrint('STEP a second workout the same day: no celebration');
    await h.goTab(Icons.fitness_center_outlined);
    await h.scrollToTop();
    await h.waitFor(find.text('Start'));
    await h.tap(find.text('Start').at(1));
    await h.waitFor(find.text('Finish'), reason: 'second workout opened');
    final sets2 = await activeSets(h);
    await checkSet(h, sets2.values.first.first);
    await h.settle(3);
    await finishWorkout(h);
    expect(find.byKey(const ValueKey('streak-celebration')), findsNothing);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
