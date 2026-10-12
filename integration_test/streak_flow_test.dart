import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/gamification/domain/streaks.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';

const _csv = 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
    '2026-09-01 08:00:00,01 hours 00 minutes 00 seconds,,Chest Press,0,143.3,8,0,0,,6-8\n';

/// The day streak the app should show, from the same rules (unit-tested separately).
Future<DayStreak> expected(AppHarness h) async {
  final rows = await h.db!.select(h.db!.sessions).get();
  final days = [for (final s in rows) s.startedAt];
  final now = DateTime.now();
  final goal = int.parse(await h.db!.getSetting('weekly_goal') ?? '6');
  expect(goal, 5, reason: 'onboarding keeps the program goal');
  final weekly = const StreakCalculator().compute(sessionDays: days, redDays: const {}, goal: goal, now: now, plannedRestWeekdays: const {3, 7});
  return const DayStreakCalculator().compute(
    weekly: weekly,
    sessionDays: days,
    now: now,
    offset: StreakOffset.decode(await h.db!.getSetting(StreakOffset.settingKey)),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Liftoff streak carries over in days; Settings edits it; Home and Profile show days', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    debugPrint('STEP first Liftoff import writes the 177-day offset (no fake sessions)');
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_csv, catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    final sessions = await tester.runAsync(() => h.db!.select(h.db!.sessions).get());
    expect(sessions, hasLength(1), reason: 'the offset is a setting, not sessions');
    await h.pumpApp();

    debugPrint('STEP Home shows the day streak');
    var want = (await tester.runAsync(() => expected(h)))!;
    expect(want.days, inInclusiveRange(176, 177));
    await h.waitFor(find.text('${want.days}-day streak'), reason: 'day streak on Home');
    expect(find.text('Longest ${want.longestDays} days'), findsOneWidget);
    expect(want.longestDays, greaterThanOrEqualTo(177));

    debugPrint('STEP Settings → Carried-over streak → 200');
    await h.scrollToTop();
    await h.tap(find.byTooltip('Settings'));
    await h.tap(find.byKey(const ValueKey('streak-offset')));
    await h.waitFor(find.text('Carried-over streak').last);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '200');
    await h.tap(find.text('OK'));
    await h.waitFor(find.text('200 d'), reason: 'settings row updated');
    await tester.pageBack();
    await h.settle();

    want = (await tester.runAsync(() => expected(h)))!;
    expect(want.days, inInclusiveRange(199, 200));
    await h.waitFor(find.text('${want.days}-day streak'), reason: 'Home follows the new offset');

    debugPrint('STEP Profile shows the streak in days');
    await h.goTab(Icons.person_outline_rounded);
    await h.waitFor(find.text('${want.days} days'), reason: 'profile streak');
    expect(find.textContaining('Longest: ${want.longestDays} days'), findsOneWidget);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
