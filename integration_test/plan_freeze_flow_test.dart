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
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
      '$d,$dur,,Chest Press,0,143.3,8,0,0,,6-8\n'
      '$d,$dur,,Chest Press,1,143.3,8,0,0,,6-8\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Plan freeze: missed reps change only the later sets of the same exercise, marked and explained', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
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
    final before = (await activeSets(h))['Chest Press']!;
    expect(before.length, greaterThan(1));
    final planned = before[1].weight;
    expect(before[1].suggestedWeight, isNotNull, reason: 'history gives a plan');
    expect(find.byKey(ValueKey('adjusted-${before[1].id}')), findsNothing);

    debugPrint('STEP set 1: type 3 reps (below 6–8) and ✓');
    await openCell(h, before[0], 'reps');
    await typeOnKeypad(h, '3');
    await h.tap(find.byKey(const ValueKey('key-hide')));
    await checkSet(h, before[0]);
    await h.settle(6);

    final after = (await activeSets(h))['Chest Press']!;
    expect(after[1].weight, lessThan(planned), reason: 'the next set moved one step lighter');
    expect(after[1].adjustedFrom, planned);
    expect(after[0].weight, planned, reason: 'the finished set stays as logged');
    final otherExercise = (await activeSets(h)).entries.firstWhere((e) => e.key != 'Chest Press');
    expect(otherExercise.value.first.adjustReason, isNull, reason: 'other exercises keep their plan');

    debugPrint('STEP the marker explains why');
    await h.waitFor(find.byKey(ValueKey('adjusted-${after[1].id}')), reason: 'marker on the changed set');
    await h.tap(find.byKey(ValueKey('adjusted-${after[1].id}')));
    await h.waitFor(find.text('Target changed'), scroll: false);
    expect(find.textContaining('3 reps at'), findsOneWidget);
    await h.shot('target-changed-explained');
    await h.tap(find.text('OK'));
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
