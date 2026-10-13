import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/gamification/domain/streaks.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/workout/data/history_repository.dart';

import 'harness.dart';

const _csv = 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
    '2026-09-01 08:00:00,01 hours 00 minutes 00 seconds,,Chest Press,0,143.3,8,0,0,,6-8\n';

/// The day streak the app should show, from the same rules (unit-tested separately).
Future<DayStreak> expected(AppHarness h) async {
  final db = h.db!;
  final catalog = await ExerciseRepository(db).watchCatalog().first;
  final history = await HistoryRepository(db).load(catalog);
  return const DayStreakCalculator().compute(
    workoutStarts: streakWorkoutStarts(history),
    now: DateTime.now(),
    offset: StreakOffset.decode(await db.getSetting(StreakOffset.settingKey)),
  );
}

/// Only one finished workout (one completed working set), [daysAgo] days ago at 10:00.
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
  // Finished last, so the history reloads with its sets in place.
  await (db.update(db.sessions)..where((t) => t.id.equals(sid))).write(const SessionsCompanion(status: Value('finished')));
}

Future<void> showStreakCard(AppHarness h) async {
  if (find.byIcon(Icons.home_outlined).evaluate().isNotEmpty) await h.goTab(Icons.home_outlined);
  await h.waitFor(find.byKey(const ValueKey('streak-card')), reason: 'Home streak card');
  await Scrollable.ensureVisible(find.byKey(const ValueKey('streak-card')).evaluate().first, alignment: 0.5);
  await h.settle(6);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Streak: three safety states on Home, reset after the 3rd rest day, Liftoff carry-over and its edit, '
      'reminder toggle, sessions this week on Profile, no weekly goal anywhere', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final db = h.db!;

    for (final (daysAgo, text, shot) in [
      (0, 'Safe: trained today', 'streak-safe'),
      (2, '1 rest day used', 'streak-one-rest-day'),
      (3, 'Last chance: train today or the streak resets', 'streak-last-chance'),
    ]) {
      debugPrint('STEP last workout $daysAgo day(s) ago → "$text"');
      await tester.runAsync(() => onlyWorkout(db, daysAgo));
      await showStreakCard(h);
      final want = (await tester.runAsync(() => expected(h)))!;
      expect(want.days, daysAgo + 1);
      await h.waitFor(find.text('${want.days}-day streak'), reason: 'days on Home', scroll: false);
      expect(find.descendant(of: find.byKey(const ValueKey('streak-safety')), matching: find.text(text), matchRoot: true), findsOneWidget);
      await h.shot(shot);
    }

    debugPrint('STEP the 3rd rest day ended → reset');
    await tester.runAsync(() => onlyWorkout(db, 4));
    await showStreakCard(h);
    await h.waitFor(find.text('0-day streak'), scroll: false);
    expect(find.text('Your next workout starts a new streak'), findsOneWidget);

    debugPrint('STEP first Liftoff import writes the 177-day offset (no fake sessions)');
    await tester.runAsync(() async {
      await db.delete(db.workoutSets).go();
      await db.delete(db.sessionExercises).go();
      await db.delete(db.sessions).go();
      final catalog = await ExerciseRepository(db).watchCatalog().first;
      final s = LiftoffImportService(db);
      await s.commit(await s.preview(_csv, catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    expect((await tester.runAsync(() => db.select(db.sessions).get()))!, hasLength(1), reason: 'the offset is a setting, not sessions');
    await h.pumpApp();
    var want = (await tester.runAsync(() => expected(h)))!;
    expect(want.days, 177);
    expect(want.longestDays, greaterThanOrEqualTo(177));
    await showStreakCard(h);
    await h.waitFor(find.text('177-day streak'), reason: 'carried-over streak on Home', scroll: false);

    debugPrint('STEP Settings: no weekly goal; Carried-over streak → 200; reminder toggle');
    await h.scrollToTop();
    await h.tap(find.byTooltip('Settings'));
    await h.waitFor(find.byKey(const ValueKey('streak-offset')));
    expect(find.text('Weekly goal'), findsNothing);
    await h.tap(find.byKey(const ValueKey('streak-offset')));
    await h.waitFor(find.text('Carried-over streak').last);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '200');
    await h.tap(find.text('OK'));
    await h.waitFor(find.text('200 d'), reason: 'settings row updated');
    await h.tap(find.byKey(const ValueKey('streak-reminder')));
    expect(await tester.runAsync(() => db.getSetting(SettingsModel.kStreakReminder)), 'false');
    await h.tap(find.byKey(const ValueKey('streak-reminder')));
    expect(await tester.runAsync(() => db.getSetting(SettingsModel.kStreakReminder)), 'true');
    await h.scrollToTop();
    await tester.pageBack();
    await h.settle();
    want = (await tester.runAsync(() => expected(h)))!;
    expect(want.days, 200);
    await h.waitFor(find.text('200-day streak'), reason: 'Home follows the new offset');

    debugPrint('STEP Profile: streak in days and sessions this week (display only)');
    await h.goTab(Icons.person_outline_rounded);
    await h.waitFor(find.text('200 days'), reason: 'profile streak');
    expect(find.textContaining('Longest: ${want.longestDays} days'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-sessions-this-week')), findsOneWidget);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
