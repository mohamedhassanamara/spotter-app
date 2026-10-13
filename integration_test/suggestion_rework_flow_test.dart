import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/coach/data/gym_repository.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/import/domain/liftoff.dart' show lbPerKg;
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';

/// My Y Raise history (10–12): 10 kg sessions, then the deliberate drop to 7.5 kg last week.
String _yRaiseCsv() {
  String d(int daysAgo) {
    final t = DateTime.now().subtract(Duration(days: daysAgo));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} 11:00:00';
  }

  String lb(double kg) => (kg * lbPerKg).toStringAsFixed(6);
  const dur = '01 hours 00 minutes 00 seconds';
  final rows = [
    for (final (days, sets) in [
      (21, [(10.0, 12), (10.0, 12), (10.0, 8)]),
      (14, [(10.0, 10), (10.0, 10), (7.5, 15)]),
      (7, [(7.5, 10), (7.5, 12), (5.0, 15)]),
    ])
      for (final (i, (kg, reps)) in sets.indexed) '${d(days)},$dur,,Dumbbell Incline Y Raise,$i,${lb(kg)},$reps,0,0,,10-12',
  ];
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n${rows.join('\n')}\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fix 6: gym equipment in Settings, per-exercise weight steps, Y Raise suggests 7.5 kg with the why chain, '
      'Form reset from the hint, nutrition line on the readiness card', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '106');
    final db = h.db!;
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(db).watchCatalog().first;
      final s = LiftoffImportService(db);
      await s.commit(await s.preview(_yRaiseCsv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();

    debugPrint('STEP Home: no nutrition data is said plainly');
    await h.waitFor(find.byKey(const ValueKey('nutrition-line')), reason: 'readiness card nutrition line');
    expect(find.textContaining('No nutrition data in Apple Health'), findsOneWidget);

    debugPrint('STEP Settings → My gym equipment');
    await h.tap(find.byTooltip('Settings'));
    await h.waitFor(find.byKey(const ValueKey('gym-dumbbells')));
    expect(find.textContaining('2.5–50 kg, 2.5 kg steps'), findsOneWidget);
    await h.tap(find.byKey(const ValueKey('gym-dumbbells')));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '2.5-40/2.5');
    await h.tap(find.text('Save'));
    await h.waitFor(find.textContaining('2.5–40 kg, 2.5 kg steps'));
    await h.tap(find.byKey(const ValueKey('gym-plate')));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '1.25');
    await h.tap(find.text('OK'));
    await h.waitFor(find.textContaining('two-sided machines and barbells in 2.5 kg (a pair)'));
    var gym = GymEquipment.decode(await tester.runAsync<String?>(() => db.getSetting(GymEquipment.key)));
    expect(gym.dumbbells.last, 40);
    expect(gym.smallestPlate, 1.25);
    await h.shot('gym-equipment');
    await h.scrollToTop();
    await tester.pageBack();
    await h.settle();

    debugPrint('STEP Upper: Y Raise suggests 7.5 kg (not 6), with the chain');
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Upper'));
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Dumbbell Incline Y Raise'));
    final session = (await tester.runAsync(() => (db.select(db.sessions)..where((t) => t.status.equals('active'))).getSingle()))!;
    final exs = (await tester.runAsync(() => (db.select(db.sessionExercises)
          ..where((t) => t.sessionId.equals(session.id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get()))!;
    final y = exs.firstWhere((e) => e.displayName == 'Dumbbell Incline Y Raise');
    expect(y.suggestedWeight, 7.5);
    await h.waitFor(find.byKey(ValueKey('form-reset-hint-${y.id}')), reason: 'the drop to 7.5 kg at 12 reps looks deliberate');
    await h.tap(find.byKey(ValueKey('prescription-${y.id}')));
    await h.waitFor(find.byKey(ValueKey('why-${y.id}')));
    for (final stage in ['Base', 'Rule', 'Readiness', 'Nutrition', 'Weight']) {
      expect(find.descendant(of: find.byKey(ValueKey('why-${y.id}')), matching: find.textContaining(stage)), findsWidgets, reason: stage);
    }
    expect(find.descendant(of: find.byKey(ValueKey('why-${y.id}')), matching: find.textContaining('7.5 kg exists in your gym')), findsOneWidget);
    await h.shot('why-chain');

    debugPrint('STEP Form reset from the hint');
    await h.tap(find.byKey(ValueKey('form-reset-hint-${y.id}')));
    await h.waitFor(find.text('Form reset'), scroll: false);
    await h.tap(find.text('OK'));
    await h.waitFor(find.textContaining('progression restarts from 7.5 kg'), scroll: false);
    final resets = GymRepository.decodeResets(await tester.runAsync<String?>(() => db.getSetting(GymRepository.formResetsKey)));
    expect(resets.values.single.weight, 7.5);

    debugPrint('STEP machine exercise → Weight steps…');
    final press = exs.first;
    await h.scrollToTop();
    await h.tap(find.byKey(ValueKey('menu-${press.id}')));
    await h.tap(find.text('Weight steps…').last);
    await h.tap(find.byKey(const ValueKey('load-stack')));
    await tester.enterText(find.byKey(const ValueKey('stack-start')), '2');
    await tester.enterText(find.byKey(const ValueKey('stack-step')), '7');
    await h.tap(find.byKey(const ValueKey('stack-save')));
    gym = GymEquipment.decode(await tester.runAsync<String?>(() => db.getSetting(GymEquipment.key)));
    expect(gym.perExercise[press.exerciseId], const StackSpec(start: 2, step: 7));
    expect(jsonDecode(gym.encode()), isA<Map<String, dynamic>>());

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
