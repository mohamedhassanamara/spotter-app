import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/import/domain/liftoff.dart' show lbPerKg;
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/workout/presentation/exercise_block.dart';
import 'package:spotter/features/workout/presentation/keypad.dart';

import 'harness.dart';

Finder _block(String name) => find.ancestor(of: find.text(name), matching: find.byType(ExerciseBlock)).first;

Finder _inBlock(String name, Finder f) => find.descendant(of: _block(name), matching: f);

/// Types [value] on the custom keypad, key by key.
Future<void> _type(AppHarness h, String value) async {
  for (final c in value.split('')) {
    if (c == '-') continue; // assisted cells start negative
    await h.tester.tap(find.byKey(ValueKey(c == '.' ? 'key-dot' : 'key-$c')));
    await h.tester.pump(const Duration(milliseconds: 30));
  }
  await h.settle(2);
}

/// Sets of the active session, in screen order.
Future<List<(SessionExercise, WorkoutSet)>> _activeSets(AppHarness h) async {
  final db = h.db!;
  final session = await (db.select(db.sessions)..where((t) => t.status.equals('active'))).getSingle();
  final exs = await (db.select(db.sessionExercises)
        ..where((t) => t.sessionId.equals(session.id))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .get();
  final out = <(SessionExercise, WorkoutSet)>[];
  for (final e in exs) {
    final sets = await (db.select(db.workoutSets)
          ..where((t) => t.sessionExerciseId.equals(e.id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    out.addAll([for (final s in sets) (e, s)]);
  }
  return out;
}

Future<void> _finish(AppHarness h) async {
  await h.scrollToTop();
  await h.tap(find.text('Finish'));
  if (find.text('Finish workout?').evaluate().isNotEmpty) {
    await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
  }
  await h.waitFor(find.text('WORKOUT COMPLETE'), timeout: const Duration(seconds: 30), reason: 'summary');
}

/// A Push session a few days ago, so PREV has something to show.
String _previousPush() {
  final t = DateTime.now().subtract(const Duration(days: 3));
  String two(int v) => v.toString().padLeft(2, '0');
  final d = '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
  String lb(double kg) => (kg * lbPerKg).toStringAsFixed(6);
  const dur = '01 hours 00 minutes 00 seconds';
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
      '$d,$dur,,High to Low Cable Fly,0,${lb(12)},12,0,0,,10-12\n'
      '$d,$dur,,High to Low Cable Fly,1,${lb(12)},11,0,0,,10-12\n'
      '$d,$dur,,Smith Machine Bench Press,0,${lb(55)},8,0,0,,6-8\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Push with the keypad only: empty-cell ✓, PREV copy, effort, drop set, rest in the header, '
      'minimize and resume, finish', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_previousPush(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();

    debugPrint('STEP Train → Push');
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Push'));
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.text('High-to-Low Cable Fly'), reason: 'Push opened');
    expect(find.text('SET'), findsWidgets);
    expect(find.text('PREV'), findsWidgets);
    expect(find.textContaining('???'), findsNothing, reason: 'rank strip never shows ???');
    await h.shot('logging-at-rest');

    var sets = (await tester.runAsync(() => _activeSets(h)))!;
    var shotKeypad = false, shotRest = false, effortCycled = false, prevCopied = false;
    double? effortRpe;
    for (final (ex, s) in sets) {
      final name = ex.displayName!;
      if (s.isWarmup) {
        // Warm-ups: accept the suggestion with ✓ on the untouched row.
        await h.tap(find.descendant(of: find.byKey(ValueKey('set-${s.id}')), matching: find.byTooltip('Complete set')));
        continue;
      }
      if (!prevCopied && name == 'High-to-Low Cable Fly') {
        debugPrint('STEP PREV copy');
        await h.tap(find.byKey(ValueKey('prev-${s.id}')));
        final copied = (await tester.runAsync(() => h.db!.select(h.db!.workoutSets).get()))!.firstWhere((x) => x.id == s.id);
        expect(copied.weight, closeTo(12, 0.01));
        expect(copied.reps, 12);
        prevCopied = true;
      } else {
        // KG → type → NEXT → REPS → type, all on the keypad.
        await h.tap(find.byKey(ValueKey('cell-kg-${s.id}')));
        await h.waitFor(find.byKey(const ValueKey('workout-keypad')), scroll: false);
        final cell = tester.getRect(find.byKey(ValueKey('cell-kg-${s.id}')));
        expect(cell.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('workout-keypad'))).top),
            reason: 'the keypad never covers the field being edited');
        await _type(h, KeypadBuffer.formatPlain(s.weight));
        await h.tap(find.byKey(const ValueKey('key-next')));
        await _type(h, '${s.reps}');
        if (!shotKeypad) {
          await h.shot('logging-keypad');
          shotKeypad = true;
        }
      }
      if (!effortCycled && name == 'Smith Machine Bench Press') {
        debugPrint('STEP cycle effort');
        final before = Effort.fromRpe(s.rpe) ?? Effort.fromRir(s.targetRir ?? ex.targetRir);
        await h.tap(find.byKey(ValueKey('effort-${s.id}')));
        await h.waitFor(find.descendant(of: find.byKey(ValueKey('effort-${s.id}')), matching: find.text(before.next.label)), scroll: false);
        effortRpe = before.next.rpe;
        effortCycled = true;
      }
      await h.tap(find.descendant(of: find.byKey(ValueKey('set-${s.id}')), matching: find.byTooltip('Complete set')));
      if (!shotRest && find.textContaining('REST ').evaluate().isNotEmpty) {
        debugPrint('STEP rest shows in the header; expand; skip');
        await h.shot('logging-resting');
        await h.tap(find.byKey(const ValueKey('workout-clock')));
        await h.waitFor(find.text('Skip'), scroll: false);
        expect(find.text('+15'), findsOneWidget);
        await h.tap(find.text('Skip'));
        expect(find.textContaining('REST '), findsNothing);
        shotRest = true;
      }
    }
    expect(shotRest, isTrue, reason: 'a working set started the rest timer');

    debugPrint('STEP drop set: ADD SET → set type D');
    const lateral = 'Standing Machine Lateral Raise';
    await h.tap(_inBlock(lateral, find.text('ADD SET')));
    sets = (await tester.runAsync(() => _activeSets(h)))!;
    final added = sets.where((x) => x.$1.displayName == lateral).last.$2;
    await h.tap(find.byKey(ValueKey('set-label-${added.id}')));
    await h.tap(find.byKey(const ValueKey('kind-drop')));
    await h.waitFor(find.descendant(of: find.byKey(ValueKey('set-${added.id}')), matching: find.text('D')), reason: 'drop set row');
    await h.tap(find.descendant(of: find.byKey(ValueKey('set-${added.id}')), matching: find.byTooltip('Complete set')));

    debugPrint('STEP minimize → mini bar → resume');
    await h.scrollToTop();
    await h.tap(find.byTooltip('Minimize workout'));
    await h.waitFor(find.byKey(const ValueKey('mini-workout-bar')), reason: 'mini bar over the tabs');
    await h.goTab(Icons.menu_book_outlined);
    expect(find.byKey(const ValueKey('mini-workout-bar')), findsOneWidget, reason: 'visible on other tabs');
    await h.tap(find.byKey(const ValueKey('mini-workout-bar')));
    await h.waitFor(find.text('High-to-Low Cable Fly'), reason: 'resumed');

    await _finish(h);
    final all = (await tester.runAsync(() => h.db!.select(h.db!.workoutSets).get()))!;
    final pushSets = all.where((x) => x.completedAt != null && x.completedAt!.isAfter(DateTime.now().subtract(const Duration(hours: 1)))).toList();
    expect(pushSets.where((x) => x.setType == 'drop'), hasLength(1));
    expect(pushSets.where((x) => !x.completed), isEmpty);
    expect(pushSets.any((x) => x.rpe == effortRpe), isTrue, reason: 'cycled effort stored');
    await h.tap(find.text('Done'));

    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Pull: assisted negative load typed on the keypad with +/−', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Pull'));
    await h.tap(find.text('Start').at(3));
    await h.waitFor(find.text('Assisted Pull-Ups'));

    final sets = (await tester.runAsync(() => _activeSets(h)))!.where((x) => x.$1.displayName == 'Assisted Pull-Ups').toList();
    final working = sets.where((x) => !x.$2.isWarmup).toList();
    expect(working.first.$2.weight, lessThan(0), reason: 'calibration starts with assistance');
    await h.waitFor(_inBlock('Assisted Pull-Ups', find.textContaining('-40')), reason: 'cells show negative assistance');

    final first = working.first.$2;
    await h.tap(find.byKey(ValueKey('cell-kg-${first.id}')));
    await _type(h, '35');
    expect(find.descendant(of: find.byKey(ValueKey('cell-kg-${first.id}')), matching: find.text('-35')), findsOneWidget);
    await h.tap(find.byKey(const ValueKey('key-sign')));
    expect(find.descendant(of: find.byKey(ValueKey('cell-kg-${first.id}')), matching: find.text('35')), findsOneWidget);
    await h.tap(find.byKey(const ValueKey('key-sign')));
    await h.tap(find.byKey(const ValueKey('key-hide')));
    for (final (_, s) in sets) {
      await h.tap(find.descendant(of: find.byKey(ValueKey('set-${s.id}')), matching: find.byTooltip('Complete set')));
    }
    final logged = (await tester.runAsync(() => h.db!.select(h.db!.workoutSets).get()))!.firstWhere((x) => x.id == first.id);
    expect(logged.weight, -35);

    await _finish(h);
    final done = (await tester.runAsync(() => h.db!.select(h.db!.workoutSets).get()))!.where((s) => s.completed && !s.isWarmup);
    expect(done.every((s) => s.weight < 0), isTrue, reason: 'assistance stored as negative load');
    await h.tap(find.text('Done'));
    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Upper: add/delete a set, replace via substitutions, background and cold restart, history, next routine',
      (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Upper'));
    await h.tap(find.text('Start'));
    await h.waitFor(find.text('Chest Press'), reason: 'workout opened with my names');
    await h.waitFor(_inBlock('Chest Press', find.textContaining('×20')), reason: '1×20 higher-rep row shows its own target');

    debugPrint('STEP complete every Chest Press set with ✓ (suggestions)');
    final chest = (await tester.runAsync(() => _activeSets(h)))!.where((x) => x.$1.displayName == 'Chest Press').toList();
    for (final (_, s) in chest) {
      await h.tap(find.descendant(of: find.byKey(ValueKey('set-${s.id}')), matching: find.byTooltip('Complete set')));
    }

    debugPrint('STEP ADD SET then delete it from the SET menu');
    const pulldown = 'Straight Arm Pulldown';
    final before = _inBlock(pulldown, find.byTooltip('Complete set')).evaluate().length;
    await h.tap(_inBlock(pulldown, find.text('ADD SET')));
    expect(_inBlock(pulldown, find.byTooltip('Complete set')).evaluate().length, before + 1);
    final added = (await tester.runAsync(() => _activeSets(h)))!.where((x) => x.$1.displayName == pulldown).last.$2;
    await h.tap(find.byKey(ValueKey('set-label-${added.id}')));
    await h.tap(find.text('Delete set'));
    expect(_inBlock(pulldown, find.byTooltip('Complete set')).evaluate().length, before);

    debugPrint('STEP replace Machine Chest Fly via the program substitutions');
    await h.tap(_inBlock('Machine Chest Fly', find.byTooltip('Exercise menu')));
    await h.tap(find.text('Replace'));
    await h.waitFor(find.text('FROM THE PROGRAM'));
    await h.tap(find.text('DB Flye'));
    await h.waitFor(find.text('Dumbbell Flyes'), reason: 'replaced exercise');
    expect(find.text('Machine Chest Fly'), findsNothing);

    debugPrint('STEP background mid-workout and resume');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(find.text('Dumbbell Flyes'), findsOneWidget);

    debugPrint('STEP cold restart: resume from Home');
    await h.pumpApp();
    await h.tap(find.text('Resume Upper'));
    await h.waitFor(find.text('Chest Press'));
    final done = (await tester.runAsync(() => h.db!.select(h.db!.workoutSets).get()))!.where((s) => s.completed).length;
    expect(done, chest.length, reason: 'logged sets survived the restart');

    await _finish(h);
    await h.tap(find.text('Done'));

    debugPrint('STEP history shows the session; Home starts Lower next');
    await h.goTab(Icons.insights_outlined);
    await h.tap(find.text('History'));
    await h.waitFor(find.textContaining('Upper'), reason: 'session in history');
    await h.goTab(Icons.home_outlined);
    await h.tap(find.text('Start Lower'));
    await h.waitFor(find.text('Lying Leg Curl'), reason: 'Lower started from Home');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
