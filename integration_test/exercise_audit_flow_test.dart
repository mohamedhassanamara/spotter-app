import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/features/tutorials/data/media_repository.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Exercise audit (Settings → Debug menu): a wrong GIF is listed, one tap removes it', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    for (var i = 0; i < 60; i++) {
      if ((await tester.runAsync(() => h.db!.select(h.db!.mediaMatches).get()))!.length > 2000) break;
      await h.settle(5);
    }

    // Break one exercise of my routines on purpose: a pec-deck-style machine row gets a barbell curl GIF.
    final target = (await tester.runAsync(() async {
      final rows = await h.db!.select(h.db!.routineExercises).get();
      final catalog = {for (final e in await h.db!.select(h.db!.exercises).get()) e.id: e.name};
      final edb = await MediaRepository.loadEdb();
      final wrong = edb.firstWhere((e) => e.name.toLowerCase() == 'ez-bar curl');
      final id = rows.first.exerciseId;
      await MediaRepository(h.db!).setManual(id, wrong, now: DateTime.now());
      return (id, catalog[id]!);
    }))!;
    final (id, name) = target;

    debugPrint('STEP Settings → Debug menu → Exercise audit lists the exercise as a problem');
    await h.goTab(Icons.person_outline_rounded);
    await h.tap(find.byTooltip('Settings'));
    await h.tap(find.text('Debug menu'));
    await h.waitFor(find.byKey(const ValueKey('exercise-audit')));
    await h.tap(find.byKey(const ValueKey('exercise-audit')));
    await h.waitFor(find.byKey(const ValueKey('audit-summary')), scroll: false);
    await h.waitFor(find.byKey(ValueKey('audit-row-$id')), scroll: false, reason: '$name has a wrong GIF');
    expect(find.textContaining('EZ-Bar Curl'), findsWidgets);
    await h.shot('exercise-audit-problem');

    debugPrint('STEP one tap: No GIF → the row leaves the To-fix list');
    await h.tap(find.byKey(ValueKey('audit-row-$id')));
    await h.waitFor(find.byKey(const ValueKey('audit-fix-no-gif')), scroll: false);
    await h.tap(find.byKey(const ValueKey('audit-fix-no-gif')));
    await h.settle(10);
    expect(find.byKey(ValueKey('audit-row-$id')), findsNothing, reason: 'fixed, no longer a problem');
    final match = await tester.runAsync(() => MediaRepository(h.db!).match(id));
    expect(match!.edbId, isNull);
    expect(match.source, 'manual');

    debugPrint('STEP All: the exercise is still listed, now with no GIF and no ✗');
    await h.tap(find.byKey(const ValueKey('audit-filter-all')));
    await h.waitFor(find.byKey(ValueKey('audit-row-$id')), reason: 'listed under All');
    await h.shot('exercise-audit-all');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
