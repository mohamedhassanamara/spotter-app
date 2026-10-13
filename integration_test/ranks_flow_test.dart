import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/gamification/data/gamification_repository.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/data/body_map.dart';
import 'package:spotter/features/ranks/data/ladder_migration.dart';
import 'package:spotter/features/ranks/presentation/anatomy_graph.dart';

import 'harness.dart';

/// Recent history: two Upper-style sessions and a Pull session (dates relative to today, so they're
/// inside the 90-day ranking window).
String _csv() {
  String d(int daysAgo) {
    final t = DateTime.now().subtract(Duration(days: daysAgo));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
  }

  const dur = '01 hours 00 minutes 00 seconds';
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
      '${d(10)},$dur,,Chest Press,0,143.3,8,0,0,,6-8\n'
      '${d(10)},$dur,,Machine Chest Fly,0,154.3,12,0,0,,10-12\n'
      '${d(10)},$dur,,Chest Supported T Bar Row,0,126.8,8,0,0,,6-8\n'
      '${d(5)},$dur,,Assisted Pull Ups,0,66.1,8,0,0,,6-8\n'
      '${d(5)},$dur,,Lat Pulldown,0,154.3,8,0,0,,6-8\n'
      '${d(5)},$dur,,EZ Bar Curl,0,88.2,8,0,0,,6-8\n';
}

/// Taps the centre of [m] on the front or back body (both are on screen side by side).
Future<void> tapMuscle(AppHarness h, BodyView view, Muscle m, {required bool back}) async {
  final rect = h.tester.getRect(find.byKey(ValueKey(back ? 'body-back' : 'body-front')));
  final b = view.bounds;
  final s = rect.width / b.width < rect.height / b.height ? rect.width / b.width : rect.height / b.height;
  final dx = rect.left + (rect.width - b.width * s) / 2;
  final dy = rect.top + (rect.height - b.height * s) / 2;
  // One side's part: the centre of both sides together is the gap between them.
  final c = view.parts.firstWhere((p) => p.muscle == m).path.getBounds().center;
  final at = Offset(dx + (c.dx - b.left) * s, dy + (c.dy - b.top) * s);
  debugPrint('TAP ${m.label} at $at (graph $rect, screen ${h.tester.view.physicalSize / h.tester.view.devicePixelRatio})');
  await h.tester.tapAt(at);
  await h.settle();
}

Finder tab(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label));

Future<void> closeSheet(AppHarness h) async {
  await h.tester.tapAt(const Offset(20, 80)); // the barrier above the sheet
  await h.settle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Ranks: regions X/Y, muscle rows and sheet, 20-muscle body graph front and back, hide an exercise; '
      'old rank badges revoked silently', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '106');

    debugPrint('STEP import recent history; a Master badge from the old standards is on file');
    await tester.runAsync(() async {
      final db = h.db!;
      final catalog = await ExerciseRepository(db).watchCatalog().first;
      final s = LiftoffImportService(db);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
      await GamificationRepository(db).unlock(['rank_master', 'first_workout'], DateTime.now());
      await db.putSetting(rankLadderVersionKey, '2');
    });
    await h.pumpApp(); // cold start runs the v3 migration
    for (var i = 0; i < 20; i++) {
      if (await tester.runAsync(() => h.db!.getSetting(rankLadderVersionKey)) == '$rankLadderVersion') break;
      await h.settle(3);
    }
    final keys = await tester.runAsync(() => GamificationRepository(h.db!).unlockedKeys());
    expect(keys, isNot(contains('rank_master')), reason: 'Master badge from the old standards is revoked');
    expect(keys, contains('first_workout'));
    expect(find.textContaining('RANK UP'), findsNothing, reason: 'no rank-down/up animation');

    debugPrint('STEP Progress → Ranks: regions with X/Y ranked');
    await h.goTab(Icons.insights_outlined);
    await h.tap(tab('Ranks'));
    await h.waitFor(find.text('OVERALL RANK'), scroll: false);
    await h.waitFor(find.textContaining('/2 ranked'), reason: 'Chest region shows X/2 ranked');

    debugPrint('STEP expand Chest, open Upper Chest');
    await h.tap(find.byKey(const ValueKey('region-chest')));
    await h.waitFor(find.text('Upper Chest'));
    expect(find.text('Lower Chest'), findsWidgets);
    await h.tap(find.text('Upper Chest'));
    await h.waitFor(find.text('CONTRIBUTING EXERCISES'), reason: 'muscle sheet');
    expect(find.text('Chest Press'), findsWidgets);
    await closeSheet(h);

    debugPrint('STEP Body graph: tap Upper Chest on the front, Lats on the back');
    final map = await tester.runAsync(BodyMap.load);
    await h.tap(tab('Body'));
    await h.waitFor(find.byType(AnatomyGraph), scroll: false);
    expect(find.byKey(const ValueKey('body-rank-header')), findsOneWidget);
    expect(find.textContaining('BODY RANK'), findsOneWidget);
    await tapMuscle(h, map!.front, Muscle.upperChest, back: false);
    await h.waitFor(find.text('CONTRIBUTING EXERCISES'), reason: 'sheet from the body graph');
    expect(find.text('Upper Chest'), findsWidgets);
    await closeSheet(h);
    await tapMuscle(h, map.back, Muscle.lats, back: true);
    await h.waitFor(find.text('Lats'), reason: 'lats sheet from the back view');
    await closeSheet(h);

    debugPrint('STEP hide Machine Chest Fly from ranks on its exercise page');
    await h.tap(tab('Ranks'));
    await h.tap(find.text('Machine Chest Fly'));
    await h.waitFor(find.byKey(const ValueKey('count-toward-ranks')), reason: 'Count toward ranks switch');
    await h.tap(find.byKey(const ValueKey('count-toward-ranks')));
    await h.scrollToTop();
    await tester.pageBack();
    await h.settle();
    await h.waitFor(find.text('HIDDEN FROM RANKS (1)'));
    // Switch it back on from its (dimmed) row in the hidden section.
    final row = find.ancestor(of: find.text('Machine Chest Fly'), matching: find.byWidgetPredicate((w) => '${w.key}'.contains('lift-rank-'))).first;
    await h.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await h.settle();
    expect(find.textContaining('HIDDEN FROM RANKS'), findsNothing);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
