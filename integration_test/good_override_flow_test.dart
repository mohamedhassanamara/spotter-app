import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/app.dart';
import 'package:spotter/app_providers.dart';
import 'package:spotter/core/db/database.dart' show WorkoutSet;
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/coach/domain/praise.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';
import 'logger_helpers.dart';

String _csv() {
  String d(int daysAgo) {
    final t = DateTime.now().subtract(Duration(days: daysAgo));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
  }

  const dur = '01 hours 00 minutes 00 seconds';
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
      '${d(7)},$dur,,Chest Press,0,132.3,5,0,0,,4-6\n'
      '${d(7)},$dur,,Chest Press,1,132.3,5,0,0,,4-6\n'
      '${d(7)},$dur,,Machine Chest Fly,0,110.2,11,0,0,,10-12\n'
      '${d(7)},$dur,,Machine Chest Fly,1,110.2,11,0,0,,10-12\n'
      '${d(7)},$dur,,Chest Supported T Bar Row,0,88.2,7,0,0,,6-8\n'
      '${d(7)},$dur,,Chest Supported T Bar Row,1,88.2,7,0,0,,6-8\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A heavier set that stays in the range is a good override: praised at most once per exercise and twice per workout, '
      'never an ego warning; below the range still is', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final db = h.db!;
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(db).watchCatalog().first;
      final s = LiftoffImportService(db);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    final container = ProviderScope.containerOf(tester.element(find.byType(SpotterApp)));
    int praised() => container.read(praiseProvider).values.fold<int>(0, (n, s) => n + s.count);

    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    final sets = await activeSets(h);
    final chest = sets['Chest Press']!, fly = sets['Machine Chest Fly']!, tbar = sets['Chest Supported T-Bar Row']!;

    Future<void> doSet(WorkoutSet s, String kg, String reps) async {
      await openCell(h, s, 'kg');
      await typeOnKeypad(h, kg);
      await h.tap(find.byKey(const ValueKey('key-next')));
      await typeOnKeypad(h, reps);
      await h.tap(find.byKey(const ValueKey('key-hide')));
      await checkSet(h, s);
      await h.settle(4);
    }

    debugPrint('STEP Chest Press 100 kg × 5: far above the suggestion, inside 4–6 → good override, praise #1');
    await doSet(chest[0], '100', '5');
    expect(praised(), 1);
    await h.waitFor(find.byKey(const ValueKey('praise-snackbar')), scroll: false, reason: 'the praise');
    final text = (find.descendant(of: find.byKey(const ValueKey('praise-snackbar')), matching: find.byType(Text)).evaluate().first.widget as Text).data!;
    expect(PraisePolicy.messages, contains(text));
    expect(find.byKey(ValueKey('good-override-${chest[0].id}')), findsOneWidget, reason: 'green chip, not the amber warning');
    await h.shot('good-override-praise');

    debugPrint('STEP the same exercise again: no second praise (once per exercise)');
    await doSet(chest[1], '100', '5');
    expect(praised(), 1);

    debugPrint('STEP a second exercise: praise #2, with different words');
    await doSet(fly[0], '90', '11');
    expect(praised(), 2);

    debugPrint('STEP a third exercise: none (two per workout)');
    await doSet(tbar[0], '80', '7');
    expect(praised(), 2);
    expect(find.byKey(ValueKey('good-override-${tbar[0].id}')), findsOneWidget, reason: 'still recognised as a good override, just not praised again');

    debugPrint('STEP below the range with extra weight is still an ego warning (reason sheet, no praise)');
    await doSet(tbar[1], '80', '3').catchError((_) {});
    await h.waitFor(find.text('Heavier than suggested and short of the range'), reason: 'ego reason sheet', scroll: false);
    expect(praised(), 2);
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
