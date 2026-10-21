import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';

String _csv() {
  String d(int daysAgo) {
    final t = DateTime.now().subtract(Duration(days: daysAgo));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
  }

  const dur = '01 hours 00 minutes 00 seconds';
  // Chest press getting heavier over four months (pounds), a leg extension block later on.
  final rows = <String>[];
  for (final (days, lb, ex) in [
    (120, 110.0, 'Chest Press'),
    (95, 132.0, 'Chest Press'),
    (70, 154.0, 'Chest Press'),
    (45, 176.0, 'Chest Press'),
    (20, 198.0, 'Chest Press'),
    (45, 200.0, 'Leg Extension'),
    (20, 240.0, 'Leg Extension'),
    (3, 220.0, 'Chest Press'),
  ]) {
    rows.add('${d(days)},$dur,,$ex,0,$lb,8,0,0,,6-8');
  }
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n${rows.join('\n')}\n';
}

void main() {
  _flow();
}

void _flow() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Rank evolution chart (overall, region, muscle) and the ladder screen', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '80');
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();

    debugPrint('STEP Progress → Ranks: the evolution chart with the imported history');
    await h.goTab(Icons.insights_outlined);
    await h.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Ranks')));
    await h.waitFor(find.byKey(const ValueKey('rank-evolution')), reason: 'evolution card');
    await h.waitFor(find.byKey(const ValueKey('evolution-now')), scroll: false, reason: 'a line was drawn (overall ranked)');
    expect(find.text('Overall'), findsWidgets);
    expect(find.byKey(const ValueKey('chart-overall')), findsOneWidget);
    await h.shot('rank-evolution-overall');

    debugPrint('STEP the range switch: Week · Month · 3 Months · Year · All, the axis adapts, the line stays');
    for (final (key, label) in [
      ('week', 'Week'),
      ('month', 'Month'),
      ('threeMonths', '3 Months'),
      ('year', 'Year'),
      ('all', 'All'),
    ]) {
      final chip = find.byKey(ValueKey('evolution-range-$key'));
      expect(chip, findsOneWidget, reason: label);
      expect(find.descendant(of: chip, matching: find.text(label)), findsOneWidget);
    }
    for (final key in ['week', 'month', 'threeMonths', 'year']) {
      await h.tap(find.byKey(ValueKey('evolution-range-$key')));
      await h.settle(6);
      expect(find.byKey(const ValueKey('chart-overall')), findsOneWidget, reason: 'the overall line draws in the $key range');
      expect(find.byKey(const ValueKey('evolution-empty')), findsNothing);
      await h.shot('rank-evolution-range-$key');
    }
    await h.tap(find.byKey(const ValueKey('evolution-range-week')));
    await h.settle(6);

    debugPrint('STEP a region and a muscle show their own line (the range stays)');
    final chips = find.descendant(of: find.byKey(const ValueKey('rank-evolution')), matching: find.byType(Scrollable)).last;
    Future<void> pick(String key) async {
      await tester.ensureVisible(find.byKey(const ValueKey('rank-evolution')));
      await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 100, scrollable: chips);
      await h.settle(2);
      await tester.tap(find.byKey(ValueKey(key)));
      await h.settle(4);
    }

    await pick('evolution-region-chest');
    await h.waitFor(find.byKey(const ValueKey('chart-region-chest')), scroll: false);
    expect(tester.widget<Text>(find.byKey(const ValueKey('evolution-series'))).data, 'Chest');
    await pick('evolution-muscle-quadriceps');
    await h.waitFor(find.byKey(const ValueKey('chart-muscle-quadriceps')), scroll: false);
    expect(tester.widget<Text>(find.byKey(const ValueKey('evolution-series'))).data, 'Quadriceps');
    await h.shot('rank-evolution-muscle');
    await h.tap(find.byKey(const ValueKey('evolution-range-all')));
    await h.settle(6);
    expect(find.byKey(const ValueKey('chart-muscle-quadriceps')), findsOneWidget);

    debugPrint('STEP the ladder: every tier, every division, where I sit, each muscle');
    await h.tap(find.byKey(const ValueKey('open-ladder')));
    await h.waitFor(find.byKey(const ValueKey('ladder-tier-immortal')), scroll: false);
    expect(find.byKey(const ValueKey('ladder-you-are-here')), findsNothing, reason: 'Immortal is not where I am');
    final list = find.descendant(of: find.byKey(const ValueKey('ladder-list')), matching: find.byType(Scrollable)).first;
    var sawYouAreHere = false;
    for (final t in ['immortal', 'olympian', 'champion', 'diamond', 'platinum', 'gold', 'silver', 'bronze', 'iron']) {
      await tester.scrollUntilVisible(find.byKey(ValueKey('ladder-tier-$t')), 200, scrollable: list);
      await h.settle(2);
      expect(find.byKey(ValueKey('ladder-tier-$t')), findsOneWidget, reason: 'tier $t on the ladder');
      sawYouAreHere = sawYouAreHere || find.byKey(const ValueKey('ladder-you-are-here')).evaluate().isNotEmpty;
    }
    expect(sawYouAreHere, isTrue, reason: 'my tier is marked');
    expect(find.byType(Table), findsWidgets, reason: 'what each tier asks for, as a table');
    expect(find.textContaining('Bench press: You:'), findsWidgets, reason: 'my e1RM under each table');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('ladder-muscle-quadriceps')), 200, scrollable: list);
    await h.shot('ladder');
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
