import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/data/body_map.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

import 'harness.dart';

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
      '${d(5)},$dur,,EZ Bar Curl,0,88.2,8,0,0,,6-8\n'
      '${d(3)},$dur,,Leg Press,0,400,10,0,0,,8-10\n'
      '${d(3)},$dur,,Leg Extension,0,180,12,0,0,,10-12\n';
}

Finder _tab(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label));

Future<void> _tapMuscle(AppHarness h, BodyView view, Muscle m, {required bool back}) async {
  final rect = h.tester.getRect(find.byKey(ValueKey(back ? 'body-back' : 'body-front')));
  final b = view.bounds;
  final s = rect.width / b.width < rect.height / b.height ? rect.width / b.width : rect.height / b.height;
  final c = view.shapes.firstWhere((p) => p.muscle == m).path.getBounds().center;
  await h.tester.tapAt(Offset(rect.left + (rect.width - b.width * s) / 2 + (c.dx - b.left) * s, rect.top + (rect.height - b.height * s) / 2 + (c.dy - b.top) * s));
  await h.tester.pump(const Duration(milliseconds: 100));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fix 2: readable body map. Callout on tap then sheet, legend only for tiers on the body, '
      'regions list under the map with muscle rows', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '106');
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    await h.goTab(Icons.insights_outlined);
    await h.tap(_tab('Body'));
    await h.waitFor(find.byKey(const ValueKey('body-front')), scroll: false);

    debugPrint('STEP the figure is big: nearly the full width');
    final front = tester.getRect(find.byKey(const ValueKey('body-front')));
    final back = tester.getRect(find.byKey(const ValueKey('body-back')));
    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(back.right - front.left, greaterThan(screenW - 20));

    debugPrint('STEP legend shows only the tiers on my body + Unranked');
    final legend = find.byKey(const ValueKey('tier-legend'));
    final shown = [for (final t in Tier.values) if (find.descendant(of: legend, matching: find.text(t.label)).evaluate().isNotEmpty) t];
    expect(shown.length, lessThan(Tier.values.length));
    expect(shown, isNotEmpty);
    expect(find.descendant(of: legend, matching: find.text('Unranked')), findsOneWidget);
    await h.shot('body-map-rank');

    debugPrint('STEP tap Lower Chest: callout first, then the sheet');
    final map = (await tester.runAsync(BodyMap.load))!;
    await _tapMuscle(h, map.front, Muscle.lowerChest, back: false);
    expect(find.byKey(const ValueKey('muscle-callout')), findsOneWidget, reason: 'callout before the sheet');
    expect(find.descendant(of: find.byKey(const ValueKey('muscle-callout')), matching: find.text('Lower Chest')), findsOneWidget);
    expect(find.text('CONTRIBUTING EXERCISES'), findsNothing);
    await h.shot('body-map-callout');
    await h.waitFor(find.text('CONTRIBUTING EXERCISES'), reason: 'sheet after the callout', scroll: false);
    await tester.tapAt(const Offset(20, 80));
    await h.settle();

    debugPrint('STEP regions list under the map: Chest · 2/2 ranked → muscle rows');
    await h.waitFor(find.text('Chest · 2/2 ranked'), reason: 'region row');
    await h.tap(find.byKey(const ValueKey('region-chest')));
    await h.waitFor(find.text('Upper Chest'), reason: 'muscle rows');
    await h.tap(find.text('Upper Chest').last);
    await h.waitFor(find.text('CONTRIBUTING EXERCISES'), reason: 'muscle sheet from the list', scroll: false);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
