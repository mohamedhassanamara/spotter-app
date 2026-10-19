import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/data/body_map.dart';
import 'package:spotter/features/ranks/data/rank_exclusions.dart';

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
      '${d(5)},$dur,,Lat Pulldown,0,154.3,8,0,0,,6-8\n';
}

Finder _tab(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label));

/// The Switch inside the row (sheet or Ranks card) that shows [name].
Finder _switchOn(String name, String keyPrefix) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byWidgetPredicate((w) => '${w.key}'.contains(keyPrefix))).first,
      matching: find.byType(Switch),
    );

bool _switchValue(Finder f) => (f.evaluate().first.widget as Switch).value;

Future<void> _tapMuscle(AppHarness h, BodyView view, Muscle m) async {
  final rect = h.tester.getRect(find.byKey(const ValueKey('body-front')));
  final b = view.bounds;
  final s = rect.width / b.width < rect.height / b.height ? rect.width / b.width : rect.height / b.height;
  final c = view.parts.firstWhere((p) => p.muscle == m).path.getBounds().center;
  await h.tester.tapAt(Offset(rect.left + (rect.width - b.width * s) / 2 + (c.dx - b.left) * s, rect.top + (rect.height - b.height * s) / 2 + (c.dy - b.top) * s));
  await h.settle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fix 1: "Counts toward rank" on the muscle sheet rows, the Ranks tab rows and the exercise page, all in sync', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '106');
    await tester.runAsync(() async {
      final catalog = await ExerciseRepository(h.db!).watchCatalog().first;
      final s = LiftoffImportService(h.db!);
      await s.commit(await s.preview(_csv(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    Future<Set<String>> hidden() async => (await tester.runAsync(() => RankExclusions(h.db!).load()))!;
    Future<RankPolicy> policy() async => (await tester.runAsync(() => RankExclusions(h.db!).policy()))!;

    debugPrint('STEP default: routine exercises count, the imported-only Lat Pulldown is off');
    await h.goTab(Icons.insights_outlined);
    await h.tap(_tab('Ranks'));
    await h.waitFor(find.text('HIDDEN FROM RANKS (1)'), reason: 'Lat Pulldown is in no routine');
    expect(await hidden(), contains('Wide-Grip_Lat_Pulldown'));
    expect((await policy()).sourceOf('Wide-Grip_Lat_Pulldown'), RankSource.off);

    debugPrint('STEP muscle sheet: switch Machine Chest Fly off on its row');
    await h.tap(_tab('Body'));
    await h.waitFor(find.byKey(const ValueKey('body-front')), scroll: false);
    final map = (await tester.runAsync(BodyMap.load))!;
    await _tapMuscle(h, map.front, Muscle.lowerChest);
    await h.waitFor(find.text('CONTRIBUTING EXERCISES'), scroll: false);
    final flySwitch = _switchOn('Machine Chest Fly', 'muscle-exercise-');
    expect(_switchValue(flySwitch), isTrue);
    await h.tap(flySwitch);
    await h.waitFor(find.textContaining('Not counted'), reason: 'row dims and says not counted, sheet stays open', scroll: false);
    expect(_switchValue(_switchOn('Machine Chest Fly', 'muscle-exercise-')), isFalse);
    final flyId = (await policy()).manual.entries.singleWhere((e) => !e.value).key;
    expect((await policy()).sourceOf(flyId), RankSource.manualOff, reason: 'a routine exercise switched off by hand');
    await h.shot('muscle-sheet-toggle');
    await h.tester.tapAt(const Offset(20, 80));
    await h.settle();

    debugPrint('STEP Ranks tab shows it hidden, switch it on there (manual on)');
    await h.tap(_tab('Ranks'));
    await h.waitFor(find.text('HIDDEN FROM RANKS (2)'));
    final flyToggle = find.descendant(of: find.byKey(ValueKey('lift-rank-$flyId')), matching: find.byKey(ValueKey('rank-toggle-$flyId')));
    await h.waitFor(flyToggle, reason: 'hidden row with its switch');
    expect(_switchValue(flyToggle), isFalse);
    await h.tap(flyToggle);
    await h.settle();
    await h.waitFor(find.text('HIDDEN FROM RANKS (1)'));
    expect((await policy()).sourceOf(flyId), RankSource.manualOn);

    debugPrint('STEP switch the imported Lat Pulldown on by hand: it stays on');
    await h.tap(_switchOn('Wide-Grip Lat Pulldown', 'lift-rank-'));
    await h.settle();
    expect(find.textContaining('HIDDEN FROM RANKS'), findsNothing);
    expect((await policy()).sourceOf('Wide-Grip_Lat_Pulldown'), RankSource.manualOn);

    debugPrint('STEP Ranks tab row → off; the exercise page agrees, and back on from there');
    await h.scrollToTop();
    await h.waitFor(find.text('Chest Press'));
    await h.tap(_switchOn('Chest Press', 'lift-rank-'));
    await h.settle();
    await h.waitFor(find.text('HIDDEN FROM RANKS (1)'));
    await h.tap(find.text('Chest Press').last);
    await h.waitFor(find.byKey(const ValueKey('count-toward-ranks')), reason: 'exercise page switch');
    expect((find.byKey(const ValueKey('count-toward-ranks')).evaluate().first.widget as SwitchListTile).value, isFalse);
    await h.tap(find.byKey(const ValueKey('count-toward-ranks')));
    expect(await hidden(), isNot(contains('Leverage_Chest_Press')));
    await h.scrollToTop();
    await tester.pageBack();
    await h.settle();
    expect(find.textContaining('HIDDEN FROM RANKS'), findsNothing);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
