import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/app_providers.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';
import 'package:spotter/features/ranks/presentation/anatomy_graph.dart';

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
      '${d(5)},$dur,,EZ Bar Curl,0,88.2,8,0,0,,6-8\n'
      '${d(3)},$dur,,Leg Press,0,400,10,0,0,,8-10\n';
}

Finder _tab(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bodyweight "what if": the target toggle on the exercise page and the Body map slider', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '106');
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();

    debugPrint('STEP Body map: What if opens a slider at the current bodyweight, nothing moves yet');
    await h.goTab(Icons.insights_outlined);
    await h.tap(_tab('Body'));
    await h.waitFor(find.byKey(const ValueKey('body-front')), scroll: false);
    Map<dynamic, RankScore?> scores() => tester.widget<AnatomyGraph>(find.byType(AnatomyGraph)).scores;
    String header() => (tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('body-rank-header')), matching: find.byType(Text)).last)).data!;
    final realScores = {...scores()};
    final realHeader = header();
    expect(find.byKey(const ValueKey('what-if-banner')), findsNothing);
    await h.tap(find.byKey(const ValueKey('what-if-button')));
    await h.waitFor(find.byKey(const ValueKey('what-if-banner')), scroll: false);
    expect(find.textContaining('Projection at'), findsOneWidget);

    debugPrint('STEP drag the slider to the heaviest bodyweight: ranks can only fall, the banner follows');
    final slider = find.byKey(const ValueKey('what-if-slider'));
    final before = (tester.widget<Slider>(slider)).value;
    await tester.drag(slider, const Offset(2000, 0));
    await h.settle();
    final heavy = tester.widget<Slider>(slider).value;
    expect(heavy, greaterThan(before));
    expect(find.text('Projection at ${heavy % 1 == 0 ? heavy.toInt() : heavy} kg'), findsOneWidget);
    final heavyScores = scores();
    var lower = 0;
    for (final e in realScores.entries) {
      final p = heavyScores[e.key];
      if (e.value == null) continue;
      expect(p!.value, lessThanOrEqualTo(e.value!.value + 1e-9), reason: 'a heavier lifter with the same lifts never ranks higher (allometric)');
      if (p.value < e.value!.value - 1e-6) lower++;
    }
    expect(lower, greaterThan(0), reason: 'the map recolors');
    await h.shot('what-if-heavy');

    debugPrint('STEP drag to the lightest: ranks rise');
    await tester.drag(slider, const Offset(-4000, 0));
    await h.settle();
    expect(tester.widget<Slider>(slider).value, lessThan(before));
    final lightScores = scores();
    expect([for (final e in realScores.entries) if (e.value != null && lightScores[e.key]!.value > e.value!.value + 1e-6) 1], isNotEmpty);

    debugPrint('STEP Reset: real ranks back, nothing saved');
    await h.tap(find.byKey(const ValueKey('what-if-reset')));
    await h.settle();
    expect(find.byKey(const ValueKey('what-if-banner')), findsNothing);
    await h.scrollToTop();
    expect(header(), realHeader);
    final back = scores();
    for (final e in realScores.entries) {
      expect(back[e.key]?.value, e.value?.value);
    }
    final container = ProviderScope.containerOf(tester.element(find.byType(AnatomyGraph)));
    final real = await tester.runAsync(() => container.read(ranksProvider.future));
    expect(real!.overall!.value, realScores.isEmpty ? isNotNull : real.overall!.value, reason: 'the stored ranks were never touched');

    debugPrint('STEP exercise page: Lift ⇄ Bodyweight on the rank-up target');
    await h.tap(_tab('Ranks'));
    await h.waitFor(find.text('Chest Press'));
    await h.tap(find.text('Chest Press').last);
    await h.waitFor(find.byKey(const ValueKey('tab-rank')), scroll: false);
    await h.tap(find.byKey(const ValueKey('tab-rank')));
    await h.waitFor(find.byKey(const ValueKey('rank-card-target')), reason: 'lift target by default');
    String target() => tester.widget<Text>(find.byKey(const ValueKey('rank-card-target'))).data ?? tester.widget<Text>(find.byKey(const ValueKey('rank-card-target'))).textSpan!.toPlainText();
    expect(target(), contains('→'));
    expect(target(), isNot(startsWith('What if')));
    final liftLine = target();
    await h.tap(find.byKey(const ValueKey('rank-target-mode-bodyweight')));
    await h.settle();
    final bwLine = target();
    expect(bwLine, startsWith('What if · '), reason: 'labelled as a projection');
    expect(bwLine, anyOf(contains('kg bodyweight →'), contains('Not reachable by bodyweight alone'), contains('More bodyweight would lower')));
    expect(bwLine, isNot(contains(liftLine)));
    await h.shot('what-if-exercise-target');
    await h.tap(find.byKey(const ValueKey('rank-target-mode-lift')));
    await h.settle();
    expect(target(), liftLine, reason: 'back to the lift target');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
