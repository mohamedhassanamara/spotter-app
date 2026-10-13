import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/domain/load_types.dart';

import 'harness.dart';
import 'logger_helpers.dart';

Future<void> startUpper(AppHarness h) async {
  await h.goTab(Icons.fitness_center_outlined);
  await h.waitFor(find.text('Start empty workout'));
  await h.scrollToTop();
  await h.tap(find.text('Start').at(0));
  await h.waitFor(find.text('Chest Press'), reason: 'Upper opened');
}

Finder cellText(int setId, String text) => find.descendant(of: find.byKey(ValueKey('cell-kg-$setId')), matching: find.text(text));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Weight steps by load type: T-bar 2.5 kg, Leverage chest press 5 kg, stack 5 kg, and a hand-picked type', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await startUpper(h);
    final sets = await activeSets(h);
    final chest = sets['Chest Press']!, fly = sets['Machine Chest Fly']!, tbar = sets['Chest Supported T-Bar Row']!;

    debugPrint('STEP T-bar row (one loading horn): + = 2.5 kg, − back down');
    await openCell(h, tbar[0], 'kg');
    await typeOnKeypad(h, '55');
    await h.tap(find.byKey(const ValueKey('key-plus-inc')));
    await h.waitFor(cellText(tbar[0].id, '57.5'), scroll: false, reason: '55 + one 2.5 kg plate');
    await h.tap(find.byKey(const ValueKey('key-minus-inc')));
    await h.tap(find.byKey(const ValueKey('key-minus-inc')));
    await h.waitFor(cellText(tbar[0].id, '52.5'), scroll: false);

    debugPrint('STEP Leverage chest press (plates on both sides): + = 5 kg');
    await h.scrollToTop();
    await openCell(h, chest[0], 'kg');
    await typeOnKeypad(h, '55');
    await h.tap(find.byKey(const ValueKey('key-plus-inc')));
    await h.waitFor(cellText(chest[0].id, '60'), scroll: false, reason: '55 + a pair of 2.5 kg plates');

    debugPrint('STEP pec deck (pin stack): + = 5 kg');
    await openCell(h, fly[0], 'kg');
    await typeOnKeypad(h, '40');
    await h.tap(find.byKey(const ValueKey('key-plus-inc')));
    await h.waitFor(cellText(fly[0].id, '45'), scroll: false);
    await h.tap(find.byKey(const ValueKey('key-hide')));

    debugPrint('STEP my gym: the pec deck is plate-loaded on one side → Weight steps… → one side');
    await h.scrollToTop();
    final flyEx = (await tester.runAsync(() => (h.db!.select(h.db!.sessionExercises)..where((t) => t.id.equals(fly[0].sessionExerciseId))).getSingle()))!;
    await h.tap(find.byKey(ValueKey('menu-${flyEx.id}')));
    await h.tap(find.text('Weight steps…').last);
    await h.waitFor(find.byKey(const ValueKey('load-plateOneSide')), scroll: false);
    expect(find.text('Plate-loaded, both sides'), findsOneWidget);
    await h.shot('weight-steps-dialog');
    await h.tap(find.byKey(const ValueKey('load-plateOneSide')));
    await h.tap(find.byKey(const ValueKey('stack-save')));
    var gym = GymEquipment.decode(await tester.runAsync<String?>(() => h.db!.getSetting(GymEquipment.key)));
    expect(gym.typeOverrides[flyEx.exerciseId], LoadType.plateOneSide);
    await openCell(h, fly[1], 'kg');
    await typeOnKeypad(h, '40');
    await h.tap(find.byKey(const ValueKey('key-plus-inc')));
    await h.waitFor(cellText(fly[1].id, '42.5'), scroll: false, reason: 'the override wins: one plate');
    await h.tap(find.byKey(const ValueKey('key-hide')));

    debugPrint('STEP Use default puts it back to the stack');
    await h.scrollToTop();
    await h.tap(find.byKey(ValueKey('menu-${flyEx.id}')));
    await h.tap(find.text('Weight steps…').last);
    await h.waitFor(find.byKey(const ValueKey('load-reset')), scroll: false);
    await h.tap(find.byKey(const ValueKey('load-reset')));
    gym = GymEquipment.decode(await tester.runAsync<String?>(() => h.db!.getSetting(GymEquipment.key)));
    expect(gym.typeOverrides, isEmpty);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Smallest plate is a setting (default 2.5 kg) and the steps follow it', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    debugPrint('STEP Settings → My gym equipment → Smallest plate');
    await h.tap(find.byTooltip('Settings'));
    await h.waitFor(find.byKey(const ValueKey('gym-plate')));
    expect(find.descendant(of: find.byKey(const ValueKey('gym-plate')), matching: find.text('2.5 kg')), findsOneWidget);
    expect(find.textContaining('T-bar, pendulum) move in 2.5 kg steps; two-sided machines and barbells in 5 kg'), findsOneWidget);
    await h.tap(find.byKey(const ValueKey('gym-plate')));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '1.25');
    await h.tap(find.text('OK'));
    await h.waitFor(find.textContaining('move in 1.25 kg steps; two-sided machines and barbells in 2.5 kg'));
    await h.shot('smallest-plate');
    await h.scrollToTop();
    await tester.pageBack();
    await h.settle();

    await startUpper(h);
    final tbar = (await activeSets(h))['Chest Supported T-Bar Row']!;
    await openCell(h, tbar[0], 'kg');
    await typeOnKeypad(h, '55');
    await h.tap(find.byKey(const ValueKey('key-plus-inc')));
    await h.waitFor(cellText(tbar[0].id, '56.25'), scroll: false, reason: 'one 1.25 kg plate');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
