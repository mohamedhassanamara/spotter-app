import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/import/domain/liftoff.dart' show lbPerKg;
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';
import 'logger_helpers.dart';

/// Recent sessions at 20 kg (Fly) and 55 kg (Smith Bench): a lighter set at the top of the range is then
/// "a deliberate step down", which offers a form reset.
String _history() {
  String d(int daysAgo) {
    final t = DateTime.now().subtract(Duration(days: daysAgo));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
  }

  String lb(double kg) => (kg * lbPerKg).toStringAsFixed(6);
  const dur = '01 hours 00 minutes 00 seconds';
  final rows = [
    for (final days in [3, 10, 17]) ...[
      '${d(days)},$dur,,High to Low Cable Fly,0,${lb(20)},12,0,0,,10-12',
      '${d(days)},$dur,,High to Low Cable Fly,1,${lb(20)},12,0,0,,10-12',
      '${d(days)},$dur,,Smith Machine Bench Press,0,${lb(55)},10,0,0,,10',
    ],
  ];
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n${rows.join('\n')}\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Form reset snackbar: goes away by itself after 3 s, swipes away, shown once per exercise per workout, '
      'never over the keypad', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_history(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    await startPush(h);
    final sets = await activeSets(h);
    final fly = sets['High-to-Low Cable Fly']!;
    final bench = sets['Smith Machine Bench Press']!;

    debugPrint('STEP a lighter set at the top of the range offers a form reset');
    await openCell(h, fly[0], 'kg');
    await typeOnKeypad(h, '15');
    await h.tap(find.byKey(const ValueKey('key-next')));
    await typeOnKeypad(h, '12');
    await checkSet(h, fly[0]);
    await h.waitFor(find.byType(SnackBar), reason: 'the offer', scroll: false);
    expect(find.textContaining('15 kg × 12, lighter than your recent 20 kg'), findsOneWidget);

    debugPrint('STEP it goes away on its own after about 3 seconds');
    final shown = Stopwatch()..start();
    while (find.byType(SnackBar).evaluate().isNotEmpty && shown.elapsed < const Duration(seconds: 8)) {
      await h.settle(2);
    }
    expect(find.byType(SnackBar), findsNothing, reason: 'auto-dismissed');
    expect(shown.elapsed.inMilliseconds, inInclusiveRange(2200, 5000), reason: 'about 3 s');

    debugPrint('STEP once per exercise: the next lighter Fly set does not offer it again');
    await openCell(h, fly[1], 'kg');
    await typeOnKeypad(h, '15');
    await h.tap(find.byKey(const ValueKey('key-next')));
    await typeOnKeypad(h, '12');
    await checkSet(h, fly[1]);
    await h.settle(10);
    expect(find.byType(SnackBar), findsNothing, reason: 'already offered for this exercise in this workout');

    debugPrint('STEP another exercise offers it; swiping it away dismisses it');
    await h.scrollToTop();
    await openCell(h, bench[0], 'kg');
    await typeOnKeypad(h, '50');
    await h.tap(find.byKey(const ValueKey('key-next')));
    await typeOnKeypad(h, '10');
    await checkSet(h, bench[0]);
    await h.waitFor(find.byType(SnackBar), reason: 'the offer for the bench', scroll: false);
    await h.shot('form-reset-snackbar');
    await tester.drag(find.byType(SnackBar), const Offset(500, 0));
    await h.settle(12);
    expect(find.byType(SnackBar), findsNothing, reason: 'swiped away');

    debugPrint('STEP still once after leaving and re-entering the workout');
    await h.scrollToTop();
    await h.tap(find.byTooltip('Minimize workout'));
    await h.waitFor(find.byKey(const ValueKey('mini-workout-bar')));
    await h.tap(find.byKey(const ValueKey('mini-workout-bar')));
    await h.waitFor(find.text('High-to-Low Cable Fly'));
    final all = await activeSets(h);
    expect(all['Smith Machine Bench Press'], isNotEmpty);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
