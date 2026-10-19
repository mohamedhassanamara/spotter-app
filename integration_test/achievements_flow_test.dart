import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/gamification/domain/achievements.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';

String _csv() {
  final rows = <String>[];
  String two(int v) => v.toString().padLeft(2, '0');
  for (var i = 0; i < 30; i++) {
    final t = DateTime.now().subtract(Duration(days: 10 + i));
    rows.add('${t.year}-${two(t.month)}-${two(t.day)} 08:00:00,01 hours 00 minutes 00 seconds,,Chest Press,0,143.3,8,0,0,,6-8');
  }
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n${rows.join('\n')}\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Achievements in six categories with bronze/silver/gold levels; three weekly challenges; nothing about suggestions',
      (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    // The cold start re-checks the achievements silently; give it a moment.
    await h.settle(20);

    debugPrint('STEP Home: three weekly challenges, none about following suggestions');
    await h.waitFor(find.text('WEEKLY CHALLENGES'), reason: 'challenge section');
    final rows = await tester.runAsync(() => h.db!.select(h.db!.quests).get());
    expect(rows!.length, 3, reason: 'three challenges this week');
    expect(rows.map((r) => r.key).toSet().length, 3, reason: 'three different kinds');
    expect(rows.map((r) => r.key), isNot(anyOf(contains('followAll'), contains('noOverride'))));
    for (final r in rows) {
      expect(r.title.toLowerCase(), isNot(anyOf(contains('suggest'), contains('override'), contains('coach'))), reason: r.title);
      expect(find.text(r.title), findsOneWidget, reason: 'shown on Home');
    }
    await h.shot('weekly-challenges');

    debugPrint('STEP Profile: the discipline card is information only');
    await h.goTab(Icons.person_outline_rounded);
    await h.waitFor(find.text('DISCIPLINE'));
    expect(find.textContaining('Information only'), findsOneWidget);

    debugPrint('STEP Profile: achievements by category, with levels');
    await h.waitFor(find.byKey(const ValueKey('achievements-count')), reason: 'achievements section');
    for (final c in AchievementCategory.values) {
      await h.waitFor(find.byKey(ValueKey('achievements-${c.name}')), reason: 'category ${c.label}');
    }
    final unlocked = await tester.runAsync(() => h.db!.select(h.db!.achievementsUnlocked).get());
    final keys = unlocked!.map((r) => r.key).toSet();
    expect(keys, containsAll(['first_workout', 'sessions_25']), reason: '30 workouts imported');
    expect(keys, isNot(contains('sessions_100')));
    expect(keys.where((k) => const {'patience', 'monk_mode', 'disciplined'}.contains(k)), isEmpty);
    await h.waitFor(find.byKey(const ValueKey('level-sessions_25')), reason: 'Bronze tag on the 25 workouts achievement');
    expect(tester.widget<Text>(find.byKey(const ValueKey('level-sessions_25'))).data, 'BRONZE');
    await h.shot('achievements');
    await h.tap(find.byKey(const ValueKey('level-sessions_100')));
    await h.waitFor(find.textContaining('Workouts · Silver'), scroll: false, reason: 'tapping a tile explains its family and level');
    expect(find.text('Finish 100 workouts.'), findsOneWidget);
    await h.tap(find.text('Close'));
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
