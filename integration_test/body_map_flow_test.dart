import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/data/body_map.dart';

import 'harness.dart';

/// A hard chest session 3 hours ago, back 2 days ago, legs 6 days ago (weights in lb, RPE empty →
/// failure, as Liftoff exports it).
String _csv() {
  String at(Duration ago) {
    final t = DateTime.now().subtract(ago);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:00';
  }

  const dur = '01 hours 00 minutes 00 seconds';
  final chest = at(const Duration(hours: 3));
  final back = at(const Duration(days: 2));
  final legs = at(const Duration(days: 6));
  final rows = <String>[
    for (var i = 0; i < 5; i++) '$chest,$dur,,Chest Press,$i,143.3,8,0,0,,6-8',
    for (var i = 0; i < 4; i++) '$chest,$dur,,Machine Chest Fly,$i,154.3,12,0,0,,10-12',
    for (var i = 0; i < 4; i++) '$back,$dur,,Lat Pulldown,$i,154.3,8,0,0,,6-8',
    for (var i = 0; i < 3; i++) '$back,$dur,,EZ Bar Curl,$i,88.2,8,0,0,,6-8',
    for (var i = 0; i < 3; i++) '$legs,$dur,,Leg Press,$i,400,10,0,0,,8-10',
  ];
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n${rows.join('\n')}\n';
}

Future<void> _tapMuscle(AppHarness h, BodyView view, Muscle m, {required bool back}) async {
  final rect = h.tester.getRect(find.byKey(ValueKey(back ? 'body-back' : 'body-front')));
  final b = view.bounds;
  final s = rect.width / b.width < rect.height / b.height ? rect.width / b.width : rect.height / b.height;
  final dx = rect.left + (rect.width - b.width * s) / 2;
  final dy = rect.top + (rect.height - b.height * s) / 2;
  final c = view.parts.firstWhere((p) => p.muscle == m).path.getBounds().center;
  await h.tester.tapAt(Offset(dx + (c.dx - b.left) * s, dy + (c.dy - b.top) * s));
  await h.settle();
}

Future<void> _closeSheet(AppHarness h) async {
  await h.tester.tapAt(const Offset(20, 80));
  await h.settle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Recovery: Home card from imported history → body map Recovery mode, tap a muscle; '
      'Rank and Volume modes; heads-up when starting a routine with fatigued muscles', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '106');
    await tester.runAsync(() async {
      final db = h.db!;
      final catalog = await ExerciseRepository(db).watchCatalog().first;
      final s = LiftoffImportService(db);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();

    debugPrint('STEP Home recovery card, seeded from the import');
    await h.waitFor(find.byKey(const ValueKey('recovery-card')), reason: 'recovery card on Home');
    expect(find.byKey(const ValueKey('recovery-fatigued')), findsOneWidget, reason: 'chest trained 3 h ago');
    expect(find.descendant(of: find.byKey(const ValueKey('recovery-fatigued')), matching: find.textContaining('chest'), matchRoot: true), findsOneWidget);
    await Scrollable.ensureVisible(find.byKey(const ValueKey('recovery-card')).evaluate().first, alignment: 0.3);
    await h.settle();
    await h.shot('home-recovery-card');

    debugPrint('STEP card → body map in Recovery mode; tap Lower Chest');
    await h.tap(find.byKey(const ValueKey('recovery-card')));
    await h.waitFor(find.byKey(const ValueKey('body-front')), scroll: false);
    await h.waitFor(find.text('Recovering 60–89%'), reason: 'recovery legend', scroll: false);
    await h.shot('body-map-recovery');
    final map = (await tester.runAsync(BodyMap.load))!;
    await _tapMuscle(h, map.front, Muscle.lowerChest, back: false);
    await h.waitFor(find.byKey(const ValueKey('recovery-pct')), reason: 'recovery sheet', scroll: false);
    expect(find.descendant(of: find.byKey(const ValueKey('recovery-band')), matching: find.text('Fatigued'), matchRoot: true), findsOneWidget);
    expect(find.byKey(const ValueKey('recovery-last-session')), findsOneWidget, reason: 'last session that hit it');
    expect(find.textContaining('Ready'), findsWidgets);
    await h.shot('recovery-sheet');
    await _closeSheet(h);

    debugPrint('STEP Lats on the back: recovering, not fatigued');
    await _tapMuscle(h, map.back, Muscle.lats, back: true);
    await h.waitFor(find.byKey(const ValueKey('recovery-pct')), scroll: false);
    expect(find.descendant(of: find.byKey(const ValueKey('recovery-band')), matching: find.text('Fatigued'), matchRoot: true), findsNothing);
    await _closeSheet(h);

    debugPrint('STEP Rank and Volume modes on the same map');
    await h.tap(find.byKey(const ValueKey('mode-ranks')));
    await h.scrollToTop();
    await h.waitFor(find.textContaining('BODY RANK'), scroll: false);
    await h.shot('body-map-rank');
    await _tapMuscle(h, map.front, Muscle.lowerChest, back: false);
    await h.waitFor(find.text('CONTRIBUTING EXERCISES'), reason: 'rank sheet', scroll: false);
    await h.shot('rank-sheet');
    await _closeSheet(h);
    await h.tap(find.byKey(const ValueKey('mode-volume')));
    await h.waitFor(find.text('On track'), scroll: false);
    await h.shot('body-map-volume');

    debugPrint('STEP start Push: one-line heads-up, dismissable, never blocking');
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Push'));
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.byKey(const ValueKey('fatigue-heads-up')), reason: 'chest still fatigued');
    expect(find.descendant(of: find.byKey(const ValueKey('fatigue-heads-up')), matching: find.textContaining('chest'), matchRoot: true), findsOneWidget);
    await h.shot('workout-heads-up');
    await h.tap(find.descendant(of: find.byKey(const ValueKey('fatigue-heads-up')), matching: find.byTooltip('Dismiss')));
    expect(find.byKey(const ValueKey('fatigue-heads-up')), findsNothing);
    expect(find.text('High-to-Low Cable Fly'), findsOneWidget, reason: 'the workout is usable as normal');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
