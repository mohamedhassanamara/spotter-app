import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/domain/gym.dart';

import 'harness.dart';
import 'logger_helpers.dart';

Finder cellText(int setId, String text) => find.descendant(of: find.byKey(ValueKey('cell-kg-$setId')), matching: find.text(text));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Max load: set in Weight steps, the keypad + stops at it', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    await h.scrollToTop();
    await h.tap(find.text('Start').at(0));
    await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
    final sets = await activeSets(h);
    final fly = sets['Machine Chest Fly']!;
    final flyEx = (await tester.runAsync(() => (h.db!.select(h.db!.sessionExercises)..where((t) => t.id.equals(fly[0].sessionExerciseId))).getSingle()))!;

    debugPrint('STEP Weight steps… → Max load 50');
    await h.scrollToTop();
    await h.tap(find.byKey(ValueKey('menu-${flyEx.id}')));
    await h.tap(find.text('Weight steps…').last);
    await h.waitFor(find.byKey(const ValueKey('max-load')), scroll: false);
    await tester.enterText(find.byKey(const ValueKey('max-load')), '50');
    await h.tap(find.byKey(const ValueKey('stack-save')));
    final gym = GymEquipment.decode(await tester.runAsync<String?>(() => h.db!.getSetting(GymEquipment.key)));
    expect(gym.maxLoads[flyEx.exerciseId], 50);

    debugPrint('STEP keypad: 45 + → 50, + again stays 50');
    await openCell(h, fly[0], 'kg');
    await typeOnKeypad(h, '45');
    await h.tap(find.byKey(const ValueKey('key-plus-inc')));
    await h.waitFor(cellText(fly[0].id, '50'), scroll: false, reason: '45 + one stack step, the max');
    await h.tap(find.byKey(const ValueKey('key-plus-inc')));
    await h.tap(find.byKey(const ValueKey('key-plus-inc')));
    await h.settle(2);
    expect(cellText(fly[0].id, '50'), findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('cell-kg-${fly[0].id}')), matching: find.text('55')), findsNothing);
    await h.tap(find.byKey(const ValueKey('key-hide')));

    debugPrint('STEP clearing the field makes it unlimited again');
    await h.scrollToTop();
    await h.tap(find.byKey(ValueKey('menu-${flyEx.id}')));
    await h.tap(find.text('Weight steps…').last);
    await h.waitFor(find.byKey(const ValueKey('max-load')), scroll: false);
    expect(find.text('50'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('max-load')), '');
    await h.tap(find.byKey(const ValueKey('stack-save')));
    final after = GymEquipment.decode(await tester.runAsync<String?>(() => h.db!.getSetting(GymEquipment.key)));
    expect(after.maxLoads, isEmpty);
    await h.dispose();
  });
}
