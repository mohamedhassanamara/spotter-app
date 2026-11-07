import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Superset sheet: the last exercise scrolls fully above the home indicator', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Push'));
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.text('High-to-Low Cable Fly'), reason: 'Push opened');
    final db = h.db!;
    final session = await tester.runAsync(() => (db.select(db.sessions)..where((t) => t.status.equals('active'))).getSingle());
    final exs = (await tester.runAsync(() => (db.select(db.sessionExercises)
          ..where((t) => t.sessionId.equals(session!.id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get()))!;
    await h.scrollToTop();
    await h.tap(find.byKey(ValueKey('menu-${exs.first.id}')));
    await h.tap(find.text('Superset with…').last);
    final last = find.byKey(ValueKey('superset-with-${exs.last.id}'));
    await h.waitFor(last, scroll: false, reason: 'the sheet lists the other exercises');
    final scrollable = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await h.settle(4);
    final view = tester.view;
    final screenBottom = (view.physicalSize.height - view.padding.bottom) / view.devicePixelRatio;
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(screenBottom + 0.5), reason: 'the last row clears the home indicator');
    expect(tester.getRect(find.byType(BottomSheet)).top, greaterThanOrEqualTo(view.padding.top / view.devicePixelRatio), reason: 'the sheet never extends past the screen');
    await h.shot('superset-sheet-bottom');
    await tester.tap(last, warnIfMissed: false);
    await h.settle(6);
    final after = (await tester.runAsync(() => (db.select(db.sessionExercises)..where((t) => t.id.equals(exs.last.id))).getSingle()))!;
    expect(after.supersetGroup, isNotNull, reason: 'the last row is tappable');
    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Routine editor: Replace lists the program substitutions first and keeps the slot', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final db = h.db!;
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Push'));
    final push = (await tester.runAsync(() => (db.select(db.routines)..where((t) => t.name.equals('Push'))).getSingle()))!;
    Future<List<RoutineExercise>> rows() => (db.select(db.routineExercises)
          ..where((t) => t.routineId.equals(push.id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final before = (await tester.runAsync(rows))!;
    final target = before.first;

    await h.tap(find.text('Push'));
    await h.waitFor(find.byKey(ValueKey('replace-${target.id}')), reason: 'a Replace button on the row');
    await h.tap(find.byKey(ValueKey('replace-${target.id}')));
    await h.waitFor(find.text('PROGRAM SUBSTITUTION'), scroll: false, reason: 'program substitutions are listed first');
    expect(find.text('Search the library'), findsOneWidget);
    await h.shot('routine-replace-sheet');
    final tiles = find.ancestor(of: find.byIcon(Icons.swap_horiz_rounded), matching: find.byType(ListTile));
    final i = tiles.evaluate().map((e) => e.widget as ListTile).toList().indexWhere((t) => t.enabled && t.onTap != null);
    expect(i, isNonNegative, reason: 'a substitution that is in the library');
    await h.tap(tiles.at(i));
    await h.settle(6);

    final after = (await tester.runAsync(rows))!;
    final row = after.first;
    expect(row.id, target.id);
    expect(row.exerciseId, isNot(target.exerciseId));
    expect((row.position, row.targetSets, row.restSeconds, row.repMin, row.repMax, row.supersetGroup, row.programSlots),
        (target.position, target.targetSets, target.restSeconds, target.repMin, target.repMax, target.supersetGroup, target.programSlots),
        reason: 'the replacement inherits the slot');
    expect(row.programRelation, 'substitution');
    expect(after.skip(1).map((r) => r.exerciseId), before.skip(1).map((r) => r.exerciseId), reason: 'the other rows are untouched');
    expect((await tester.runAsync(() => db.select(db.sessionExercises).get()))!, isEmpty, reason: 'no history was touched');

    debugPrint('STEP the next workout started from the routine uses the replacement');
    await tester.pageBack();
    await h.settle(6);
    await h.scrollToTop();
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.text('Pec Deck'), reason: 'Push opened');
    final started = (await tester.runAsync(() => (db.select(db.sessionExercises)..orderBy([(t) => OrderingTerm.asc(t.position)])).get()))!;
    expect(started.first.exerciseId, row.exerciseId);
    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Rank chart: tap selects, outside dismisses, edges are visible, tier names are whole', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '80');
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    await h.goTab(Icons.insights_outlined);
    await h.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Ranks')));
    await h.waitFor(find.byKey(const ValueKey('evolution-now')), scroll: false, reason: 'a line was drawn');

    final tooltip = find.byKey(const ValueKey('evolution-tooltip'));
    final plot = find.byKey(const ValueKey('evolution-plot'));
    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    Future<void> tapAt(double dx) async {
      await tester.ensureVisible(plot);
      await h.settle(2);
      final r = tester.getRect(plot);
      await tester.tapAt(Offset(r.left + dx, r.center.dy));
      await h.settle(4);
    }

    Future<void> checkChart(String what) async {
      await Scrollable.ensureVisible(tester.element(find.byKey(const ValueKey('rank-evolution'))), alignment: 0.1);
      await h.settle(3);
      await tester.ensureVisible(plot);
      await h.settle(2);
      final r = tester.getRect(plot);
      final tierNames = {for (final t in Tier.values) t.label};
      for (final e in find.descendant(of: plot, matching: find.byType(Text)).evaluate()) {
        final t = (e.widget as Text).data ?? '';
        final box = tester.getRect(find.byWidget(e.widget));
        expect(box.left, greaterThanOrEqualTo(r.left - 0.5), reason: '$what: "$t" is clipped on the left');
        expect(box.right, lessThanOrEqualTo(r.right + 0.5), reason: '$what: "$t" is clipped on the right');
        if (tierNames.any((n) => n.startsWith(t) && n != t && t.isNotEmpty && t.length >= 3 && !t.contains(' '))) fail('$what: tier label "$t" is cut short');
      }
      // Far left, middle, far right of the plot: each selects a point; the tooltip stays on screen and inside the chart.
      for (final dx in [64.0, r.width / 2, r.width - 2]) {
        await tapAt(dx);
        expect(tooltip, findsOneWidget, reason: '$what: a tap at $dx selects a point');
        final tip = tester.getRect(tooltip);
        expect(tip.left, greaterThanOrEqualTo(r.left - 0.5), reason: '$what: tooltip off the left edge');
        expect(tip.right, lessThanOrEqualTo(r.right + 0.5), reason: '$what: tooltip off the right edge');
        expect(tip.right, lessThanOrEqualTo(screenW), reason: '$what: tooltip off-screen');
        expect(find.descendant(of: tooltip, matching: find.textContaining('Score')), findsOneWidget);
      }
      // Tapping another point moves the tooltip.
      await tapAt(64);
      final left = tester.getRect(tooltip).center;
      await tapAt(r.width - 2);
      expect(tester.getRect(tooltip).center, isNot(left), reason: '$what: the tooltip moved to the other point');
      // Tapping the tooltip keeps it; tapping outside the chart dismisses it.
      await tester.tap(tooltip, warnIfMissed: false);
      await h.settle(3);
      expect(tooltip, findsOneWidget, reason: '$what: tapping the tooltip keeps it');
      await tester.tap(find.byKey(const ValueKey('evolution-series')));
      await h.settle(3);
      expect(tooltip, findsNothing, reason: '$what: tapping outside dismisses');
    }

    await Scrollable.ensureVisible(tester.element(find.byKey(const ValueKey('rank-evolution'))), alignment: 0.1);
    await h.settle(3);
    await tapAt(64);
    await h.shot('rank-chart-selected');
    await tester.tap(find.byKey(const ValueKey('evolution-series')));
    await h.settle(3);
    for (final key in ['week', 'month', 'threeMonths', 'year', 'all']) {
      await h.tap(find.byKey(ValueKey('evolution-range-$key')));
      await h.settle(6);
      if (find.byKey(const ValueKey('evolution-empty')).evaluate().isNotEmpty) continue;
      await checkChart('overall/$key');
    }

    final chips = find.descendant(of: find.byKey(const ValueKey('rank-evolution')), matching: find.byType(Scrollable)).last;
    for (final (chip, chart) in [('evolution-region-chest', 'chart-region-chest'), ('evolution-muscle-quadriceps', 'chart-muscle-quadriceps')]) {
      await tester.ensureVisible(find.byKey(const ValueKey('rank-evolution')));
      await tester.scrollUntilVisible(find.byKey(ValueKey(chip)), 100, scrollable: chips);
      await h.settle(2);
      await tester.tap(find.byKey(ValueKey(chip)));
      await h.settle(4);
      await h.waitFor(find.byKey(ValueKey(chart)), scroll: false);
      if (find.byKey(const ValueKey('evolution-empty')).evaluate().isNotEmpty) continue;
      await checkChart(chart);
    }
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
