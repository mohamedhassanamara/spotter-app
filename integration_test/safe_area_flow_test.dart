import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/router.dart';

import 'harness.dart';
import 'logger_helpers.dart';

/// Safe-area audit on the real device screen: top and bottom text clear of the Dynamic Island / status bar and of
/// the home indicator, on every main screen and sheet. Run it with
///   `tool/device_shots.sh SIM_ID docs/screenshots/safearea &`
///   flutter test integration_test/safe_area_flow_test.dart -d SIM_ID --dart-define=SHOTS_DIR=$PWD/docs/screenshots/safearea
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Safe area: every screen and sheet clears the status bar, Dynamic Island, home indicator, keyboard and keypad', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    final problems = <String>[];

    ({double top, double bottom, double height}) insets() {
      final v = tester.view;
      return (top: v.padding.top / v.devicePixelRatio, bottom: v.padding.bottom / v.devicePixelRatio, height: v.physicalSize.height / v.devicePixelRatio);
    }

    List<ScrollPosition> verticalScrollables() => [
          for (final e in find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).evaluate())
            if (e is StatefulElement && (e.state as ScrollableState).position.hasPixels) (e.state as ScrollableState).position,
        ];

    /// Visible text boxes on screen.
    List<(String, Rect)> texts() {
      final out = <(String, Rect)>[];
      for (final e in find.byType(Text).evaluate()) {
        final box = e.renderObject;
        if (box is! RenderBox || !box.attached || !box.hasSize) continue;
        final r = box.localToGlobal(Offset.zero) & box.size;
        final t = (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '';
        if (t.trim().isEmpty || r.bottom <= 0 || r.top >= insets().height) continue;
        // Skip what is scrolled out of its viewport (clipped): painted but not visible.
        out.add((t, r));
      }
      return out;
    }

    /// [name]: screenshot + checks. Top: nothing under the status bar at rest. Bottom: with every list scrolled to
    /// its end, nothing under the home indicator.
    Future<void> audit(String name, {bool bottom = true}) async {
      await h.settle(6);
      final i = insets();
      for (final p in verticalScrollables()) {
        p.jumpTo(p.minScrollExtent);
      }
      await h.settle(3);
      await h.deviceShot(name);
      for (final (t, r) in texts()) {
        if (r.top < i.top - 1) problems.add('$name: "$t" is under the status bar / Dynamic Island (top ${r.top.toStringAsFixed(1)} < ${i.top.toStringAsFixed(1)})');
      }
      if (bottom) {
        for (final p in verticalScrollables()) {
          p.jumpTo(p.maxScrollExtent);
        }
        await h.settle(3);
        for (final (t, r) in texts()) {
          if (r.bottom > i.height - i.bottom + 1) {
            problems.add('$name: "$t" is under the home indicator (bottom ${r.bottom.toStringAsFixed(1)} > ${(i.height - i.bottom).toStringAsFixed(1)})');
          }
        }
        for (final p in verticalScrollables()) {
          p.jumpTo(p.minScrollExtent);
        }
        await h.settle(2);
      }
    }

    GoRouter router() => GoRouter.of(tester.element(find.byType(Scaffold).first));
    Future<void> go(String path) async {
      router().go(path);
      await h.settle(8);
    }

    Future<void> push(String path) async {
      router().push(path);
      await h.settle(8);
    }

    debugPrint('STEP onboarding');
    await audit('00-onboarding');
    await h.onboard();

    debugPrint('STEP main tabs');
    await go(Routes.home);
    await audit('01-home');
    await go(Routes.train);
    await audit('02-train');
    await go(Routes.library);
    await audit('03-library');
    await go(Routes.progress);
    await audit('04-progress-body');
    for (final (i, label) in ['Ranks', 'Lifts'].indexed) {
      final tab = find.descendant(of: find.byType(TabBar), matching: find.text(label));
      if (tab.evaluate().isEmpty) continue;
      await h.tap(tab);
      await audit('0${5 + i}-progress-${label.toLowerCase()}');
    }
    await go(Routes.profile);
    await audit('07-profile');

    debugPrint('STEP settings and sub screens');
    await push(Routes.settings);
    await audit('08-settings');
    await push(Routes.importLiftoff);
    await audit('09-import-liftoff');
    router().pop();
    await h.settle(4);
    await push(Routes.errorLog);
    await audit('10-error-log');
    router().pop();
    await h.settle(4);
    await push(Routes.debug);
    await audit('11-debug');
    router().pop();
    router().pop();
    await h.settle(4);

    debugPrint('STEP library pushes: exercise detail, new exercise, picker');
    await push(Routes.exercise('Thigh_Adductor'));
    await audit('12-exercise-detail');
    await push(Routes.exerciseHistory('Thigh_Adductor'));
    await audit('13-exercise-history');
    router().pop();
    router().pop();
    await h.settle(4);
    await push(Routes.newExercise);
    await audit('14-new-exercise');
    router().pop();
    await h.settle(4);
    await push(Routes.pickExercise);
    await audit('15-pick-exercise');
    router().pop();
    await h.settle(4);

    debugPrint('STEP routine editor');
    final routineId = (await tester.runAsync(() => h.db!.select(h.db!.routines).get()))!.first.id;
    await push(Routes.routine(routineId));
    await audit('16-routine-editor');
    router().pop();
    await h.settle(4);

    debugPrint('STEP workout, keypad, sheets');
    await go(Routes.train);
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'));
    await audit('17-workout');
    final sets = await activeSets(h);
    await openCell(h, sets['Chest Press']![0], 'kg');
    await h.settle(4);
    await h.deviceShot('18-workout-keypad');
    final i = insets();
    final keypad = tester.getRect(find.byKey(const ValueKey('workout-keypad')));
    if (keypad.bottom > i.height + 0.5) problems.add('keypad extends below the screen');
    final keyBox = tester.getRect(find.byKey(const ValueKey('key-hide')));
    if (keyBox.bottom > i.height - i.bottom + 1) problems.add('keypad: the bottom key is under the home indicator (${keyBox.bottom} > ${i.height - i.bottom})');
    await h.tap(find.byKey(const ValueKey('key-hide')));
    await checkSet(h, sets['Chest Press']![0]);
    await h.settle(4);
    await h.tap(find.byKey(const ValueKey('workout-clock')));
    await h.waitFor(find.text('Skip'), scroll: false);
    await audit('19-rest-sheet', bottom: false);
    final skip = tester.getRect(find.text('Skip'));
    if (skip.bottom > i.height - i.bottom + 1) problems.add('rest sheet: Skip is under the home indicator');
    await h.tap(find.text('Skip'));
    await h.settle(4);
    await h.tap(find.byTooltip('Minimize workout'));
    await h.settle(6);
    await audit('20-mini-workout-bar', bottom: false);
    await push(Routes.workout);
    await h.settle(4);
    await h.tap(find.byKey(ValueKey('menu-${(await tester.runAsync(() => h.db!.select(h.db!.sessionExercises).get()))!.first.id}')));
    await h.settle(3);
    await h.deviceShot('21-exercise-menu');
    await tester.tapAt(const Offset(5, 400));
    await h.settle(3);
    await h.tap(find.text('Add exercise'));
    await h.waitFor(find.byType(TextField), scroll: false);
    await tester.showKeyboard(find.byType(TextField).first);
    await h.settle(6);
    await h.deviceShot('22-add-exercise-with-keyboard');
    final field = tester.getRect(find.byType(TextField).first);
    if (field.bottom > i.height - tester.view.viewInsets.bottom / tester.view.devicePixelRatio) problems.add('search field hidden by the keyboard');
    router().pop();
    await h.settle(4);

    debugPrint('STEP summary and rank-up');
    await go(Routes.workout);
    await h.scrollToTop();
    await h.tap(find.text('Finish'));
    if (find.text('Finish workout?').evaluate().isNotEmpty) {
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
    }
    await h.waitForSummary();
    await audit('23-summary');
    await go('/settings/debug/rank-up-preview');
    await audit('24-rank-up', bottom: false);

    if (problems.isNotEmpty) debugPrint('SAFE AREA PROBLEMS:\n${problems.join('\n')}');
    expect(problems, isEmpty, reason: problems.join('\n'));
    await h.dispose();
  });
}
