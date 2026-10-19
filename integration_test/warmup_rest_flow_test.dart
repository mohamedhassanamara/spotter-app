import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:spotter/app.dart';
import 'package:spotter/core/providers.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';

import 'harness.dart';
import 'logger_helpers.dart';

String _csv() {
  final t = DateTime.now().subtract(const Duration(days: 7));
  String two(int v) => v.toString().padLeft(2, '0');
  final d = '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
  const dur = '01 hours 00 minutes 00 seconds';
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
      '$d,$dur,,Chest Press,0,132.3,5,0,0,,4-6\n'
      '$d,$dur,,Chest Press,1,132.3,5,0,0,,4-6\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Rest after warm-ups: 45 s between warm-ups, 1:30 before the first working set, then the program\'s rest', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    final container = ProviderScope.containerOf(tester.element(find.byType(SpotterApp)));
    int? restTotal() => container.read(currentSettingsProvider).restTotalSeconds;
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    // Warm-up sets of the chest press, in order, then its working sets.
    final active = (await tester.runAsync(() => (h.db!.select(h.db!.sessions)..where((t) => t.status.equals('active'))).getSingle()))!;
    final ex = (await tester.runAsync(() => (h.db!.select(h.db!.sessionExercises)..where((t) => t.sessionId.equals(active.id))).get()))!
        .firstWhere((e) => e.exerciseId == 'Leverage_Chest_Press');
    final all = (await tester.runAsync(() => h.db!.customSelect('SELECT * FROM workout_sets WHERE session_exercise_id = ? ORDER BY position', variables: [Variable.withInt(ex.id)]).get()))!
        .map((r) => h.db!.workoutSets.map(r.data))
        .toList();
    final warmups = all.where((s) => s.isWarmup).toList();
    final working = all.where((s) => !s.isWarmup).toList();
    expect(warmups.length, greaterThanOrEqualTo(2), reason: 'the program lists 2–3 warm-ups for the chest press');

    debugPrint('STEP ✓ warm-up 1 → 0:45 rest');
    await checkSet(h, warmups[0]);
    await h.waitFor(find.textContaining('REST '), scroll: false);
    expect(restTotal(), 45);
    debugPrint('STEP ✓ the next warm-up → 0:45 again, unless it was the last one');
    for (var i = 1; i < warmups.length; i++) {
      await checkSet(h, warmups[i]);
      await h.settle(4);
      expect(restTotal(), i == warmups.length - 1 ? 90 : 45, reason: 'warm-up ${i + 1} of ${warmups.length}');
    }
    debugPrint('STEP ✓ the first working set → the program\'s own rest (Chest Press: 3 min)');
    await checkSet(h, working[0]);
    await h.settle(4);
    expect(restTotal(), ex.restSeconds);
    expect(ex.restSeconds, 180);
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
