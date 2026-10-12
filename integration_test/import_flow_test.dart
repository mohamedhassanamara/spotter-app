import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/features/import/presentation/liftoff_import_screen.dart';

import 'harness.dart';

/// Same shape as the owner's export (see docs/DECISIONS.md "Liftoff import"): pounds, 0-based Set
/// Order, empty Workout Name, rep schemes in Notes, assisted machines with positive assistance,
/// a cardio row and an empty 18-second workout.
const _csv = '''Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes
2026-09-01 08:00:00,01 hours 10 minutes 00 seconds,,Chest Press,0,132.277357311,6,0,0,,2*4-6/20
2026-09-01 08:00:00,01 hours 10 minutes 00 seconds,,Chest Press,1,132.277357311,6,0,0,,2*4-6/20
2026-09-01 08:00:00,01 hours 10 minutes 00 seconds,,Chest Press,2,88.184904874,20,0,0,,2*4-6/20
2026-09-01 08:00:00,01 hours 10 minutes 00 seconds,,Machine Chest Fly,0,110.2311310925,12,0,0,,10-12   D
2026-09-01 08:00:00,01 hours 10 minutes 00 seconds,,Chest Supported T Bar Row,0,88.184904874,9,0,0,8,
2026-09-01 08:00:00,01 hours 10 minutes 00 seconds,,Walking,0,0,0,4.828,2400,,
2026-09-03 18:30:00,00 hours 55 minutes 30 seconds,,Assisted Pull Ups,1,66.1386786555,7,0,0,,6-8
2026-09-03 18:30:00,00 hours 55 minutes 30 seconds,,Assisted Pull Ups,0,66.1386786555,8,0,0,,6-8
2026-09-03 18:30:00,00 hours 55 minutes 30 seconds,,Dragon Flag,0,0,5,0,0,,
2026-09-03 18:30:00,00 hours 55 minutes 30 seconds,,Zercher Good Morning Hop,0,44.092452437,10,0,0,,
2026-09-04 07:00:00,00 hours 00 minutes 18 seconds,,,,,,,,,
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Settings → Import from Liftoff: preview, fix an unmatched name, import, re-import is a no-op, '
      'next workout suggests from the imported sessions', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh(overrides: [liftoffCsvSourceProvider.overrideWithValue(() async => _csv)]);
    await h.onboard();

    debugPrint('STEP Home → Settings → Import from Liftoff');
    await h.tap(find.byTooltip('Settings'));
    await h.tap(find.text('Import from Liftoff'));
    await h.tap(find.text('Choose CSV file'));

    debugPrint('STEP preview');
    await h.waitFor(find.textContaining('Sep 1, 2026 → Sep 3, 2026'), reason: 'preview date range', scroll: false);
    expect(find.textContaining('2 rows skipped'), findsOneWidget);
    expect(find.text('2'), findsWidgets, reason: 'new sessions');
    expect(find.text('9'), findsOneWidget, reason: 'new sets');
    await h.waitFor(find.text('CHECK THESE (1)'));
    await h.waitFor(find.text('Import 2 sessions'));
    await h.scrollToTop();

    debugPrint('STEP pick an exercise for the unmatched name');
    await h.tap(find.text('Zercher Good Morning Hop'));
    await h.waitFor(find.byType(TextField), reason: 'exercise picker');
    await tester.enterText(find.byType(TextField).first, 'Good Morning');
    await h.settle(4);
    await h.tap(find.text('Good Morning').last);
    await h.waitFor(find.text('PICKED'), reason: 'manual pick applied');
    expect(find.textContaining('CHECK THESE'), findsNothing);

    debugPrint('STEP import: no bodyweight known yet, so the app asks for it');
    await tester.runAsync(() => h.db!.delete(h.db!.bodyWeights).go());
    await h.tap(find.text('Import 2 sessions'));
    await h.waitFor(find.text('Your bodyweight'), reason: 'bodyweight prompt');
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '107');
    await h.tap(find.text('OK'));
    await h.waitFor(find.text('IMPORT COMPLETE'), timeout: const Duration(seconds: 30));
    expect(find.text('2 sessions · 9 sets'), findsOneWidget);
    expect(find.text('1 custom exercises created'), findsOneWidget, reason: 'Dragon Flag from the name map');

    final sessions = await tester.runAsync(() => h.db!.select(h.db!.sessions).get());
    expect(sessions!.map((s) => s.source).toSet(), {'liftoff'});
    final bw = await tester.runAsync(() => h.db!.select(h.db!.bodyWeights).get());
    expect(bw!.single.kg, 107);
    // The picked exercise is whichever "Good Morning" the list showed (the merged library has variants).
    final picked = await tester.runAsync(() => h.db!.customSelect(
        "SELECT se.id FROM session_exercises se JOIN exercises e ON e.id = se.exercise_id WHERE e.name = 'Good Morning'").get());
    expect(picked, hasLength(1));
    final pullSets = await tester.runAsync(() => h.db!.customSelect(
          'SELECT ws.weight AS w FROM workout_sets ws JOIN session_exercises se ON se.id = ws.session_exercise_id '
          "WHERE se.exercise_id = 'sp_assisted_pull_up_machine'").get());
    expect(pullSets!.every((r) => r.read<double>('w') < 0), isTrue, reason: 'assistance stored as negative load');
    await h.tap(find.text('Done'));

    debugPrint('STEP re-import the same file');
    await h.tap(find.text('Import from Liftoff'));
    await h.tap(find.text('Choose CSV file'));
    await h.waitFor(find.textContaining('2 already imported'), scroll: false);
    await h.waitFor(find.text('Nothing new to import'));
    await tester.pageBack();
    await h.settle();
    await tester.pageBack();
    await h.settle();

    debugPrint('STEP start Upper: Chest Press suggestion comes from the imported sessions');
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Upper'));
    await h.tap(find.text('Start'));
    await h.waitFor(find.text('Chest Press'));
    final ex = await tester.runAsync(() => (h.db!.select(h.db!.sessionExercises)
          ..where((t) => t.exerciseId.equals('Leverage_Chest_Press'))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingle());
    expect(ex!.suggestionKind, isNot('calibration'));
    expect(ex.suggestedWeight, greaterThanOrEqualTo(60));

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
