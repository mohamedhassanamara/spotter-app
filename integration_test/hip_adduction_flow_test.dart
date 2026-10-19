import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/data/rank_exclusions.dart';

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
      '${d(12)},$dur,,Hip Adduction,0,99.2,12,0,0,,\n'
      '${d(12)},$dur,,Hip Adduction,1,99.2,12,0,0,,\n'
      '${d(6)},$dur,,Hip Adduction,0,110.2,12,0,0,,\n'
      '${d(6)},$dur,,Hip Abduction,0,110.2,12,0,0,,\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Machine Seated Hip Adduction: one exercise for Liftoff history and the workout, enabled for ranks, '
      'suggested from history, named and tappable in Ranks', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '80');
    final db = h.db!;
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(db).watchCatalog().first;
      final s = LiftoffImportService(db);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    Future<RankPolicy> policy() async => (await tester.runAsync(() => RankExclusions(db).policy()))!;

    debugPrint('STEP search the library: exactly one hip adduction machine');
    await startPush(h);
    await h.tap(find.text('Add exercise'));
    await h.waitFor(find.byType(TextField), scroll: false);
    await tester.enterText(find.byType(TextField).first, 'seated hip adduction');
    await h.settle(6);
    await h.waitFor(find.text('Machine Seated Hip Adduction'));
    expect(find.text('Machine Seated Hip Adduction'), findsOneWidget, reason: 'the duplicate entries are gone');
    expect(find.text('Seated Hip Adduction'), findsNothing);
    await h.tap(find.text('Machine Seated Hip Adduction').first);
    await h.waitFor(find.text('Machine Seated Hip Adduction'), reason: 'added mid-workout');

    debugPrint('STEP it is suggested from the Liftoff history, not Calibration');
    final ex = (await tester.runAsync(() => (db.select(db.sessionExercises)..orderBy([(t) => OrderingTerm.desc(t.id)])).get()))!.first;
    expect(ex.exerciseId, 'Thigh_Adductor', reason: 'same id the import used');
    expect(ex.suggestionKind, isNot('calibration'));
    expect(ex.suggestedWeight, isNotNull);
    expect(ex.suggestedWeight, greaterThanOrEqualTo(45));
    final sets = (await tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(ex.id))).get()))!
        .where((s) => !s.isWarmup)
        .toList();
    expect(sets.first.suggestedWeight, isNotNull);
    // Item 11: an exercise added mid-workout starts with exactly one working set, prefilled from history.
    expect(sets, hasLength(1), reason: 'exactly 1 working set');
    expect(sets.first.weight, ex.suggestedWeight);
    expect(sets.first.reps, ex.suggestedReps);
    expect(sets.first.reps, greaterThan(0));
    expect(ex.targetSets, 1);

    debugPrint('STEP ADD SET adds a second one, copying the first');
    await h.tap(find.byKey(ValueKey('add-set-${ex.id}')));
    await h.settle(4);
    final two = (await tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(ex.id) & t.isWarmup.equals(false))).get()))!;
    expect(two, hasLength(2));

    debugPrint('STEP a completed working set: counts toward ranks, strip is not "Hidden from ranks"');
    await h.waitFor(find.byKey(ValueKey('set-${sets[0].id}')));
    await checkSet(h, sets[0]);
    if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    expect((await setRow(h, sets[0].id)).completed, isTrue);
    expect((await policy()).isOn('Thigh_Adductor'), isTrue);
    expect(find.text('Hidden from ranks'), findsNothing);

    debugPrint('STEP Progress → Ranks: one row, with the logged name, tapping opens the exercise');
    await h.scrollToTop();
    await h.tap(find.byTooltip('Minimize workout'));
    await h.goTab(Icons.insights_outlined);
    await h.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Ranks')));
    await h.waitFor(find.byKey(const ValueKey('lift-rank-Thigh_Adductor')), reason: 'ranked row');
    expect(find.descendant(of: find.byKey(const ValueKey('lift-rank-Thigh_Adductor')), matching: find.text('Machine Seated Hip Adduction')), findsOneWidget);
    expect(find.text('Hip Adduction'), findsNothing, reason: 'no separate "Hip Adduction" entry');
    await h.shot('ranks-hip-adduction');
    await h.tap(find.byKey(const ValueKey('lift-rank-Thigh_Adductor')));
    await h.waitFor(find.text('Machine Seated Hip Adduction'), scroll: false);
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
