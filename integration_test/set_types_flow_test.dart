import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/workout/domain/set_kinds.dart';

import 'harness.dart';

/// Sets of one session exercise, in order.
Future<List<WorkoutSet>> _sets(AppHarness h, int sessionExerciseId) => (h.db!.select(h.db!.workoutSets)
      ..where((t) => t.sessionExerciseId.equals(sessionExerciseId))
      ..orderBy([(t) => OrderingTerm.asc(t.position)]))
    .get();

Future<List<SessionExercise>> _exercises(AppHarness h) async {
  final db = h.db!;
  final session = await (db.select(db.sessions)..where((t) => t.status.equals('active'))).getSingle();
  return (db.select(db.sessionExercises)
        ..where((t) => t.sessionId.equals(session.id))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .get();
}

Future<void> _complete(AppHarness h, WorkoutSet s) =>
    h.tap(find.descendant(of: find.byKey(ValueKey('set-${s.id}')), matching: find.byTooltip('Complete set')));

Future<void> _setMenu(AppHarness h, WorkoutSet s, String key) async {
  await h.tap(find.byKey(ValueKey('set-label-${s.id}')));
  await h.tap(find.byKey(ValueKey(key)));
}

/// Taps [f] after scrolling it clear of the pinned workout header.
Future<void> _tapClear(AppHarness h, Finder f) async {
  await h.waitFor(f);
  await Scrollable.ensureVisible(f.evaluate().first, alignment: 0.5);
  await h.settle(4);
  await h.tester.tap(f);
  await h.settle();
}

bool _resting() => find.textContaining('REST ').evaluate().isNotEmpty;

Future<void> _skipRest(AppHarness h) async {
  if (!_resting()) return;
  await h.scrollToTop();
  await h.tap(find.byKey(const ValueKey('workout-clock')));
  await h.tap(find.text('Skip'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Drop sets (several, pre-filled lighter, no rest), myo-rep cycle (5 s rest), static hold, '
      'program technique creates its follow-ups', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Push'));
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.text('High-to-Low Cable Fly'));

    final exs = (await tester.runAsync(() => _exercises(h)))!;
    final fly = exs.first;
    var sets = (await tester.runAsync(() => _sets(h, fly.id)))!;
    final w1 = sets.firstWhere((s) => s.isWorkingSet);

    debugPrint('STEP two drops under set 1');
    await _setMenu(h, w1, 'follow-drop');
    await _setMenu(h, w1, 'follow-drop');
    sets = (await tester.runAsync(() => _sets(h, fly.id)))!;
    final i = sets.indexWhere((s) => s.id == w1.id);
    final d1 = sets[i + 1], d2 = sets[i + 2];
    expect([d1.kind, d2.kind], [SetKind.drop, SetKind.drop]);
    expect(d1.weight, lessThan(w1.weight));
    expect(d2.weight, lessThan(d1.weight));
    await h.waitFor(find.descendant(of: find.byKey(ValueKey('set-${d1.id}')), matching: find.text('D')), reason: 'drop row');
    await h.waitFor(find.descendant(of: find.byKey(ValueKey('set-${d1.id}')), matching: find.textContaining('%')), reason: 'drop shows its %');
    await h.shot('drop-sets');

    debugPrint('STEP no rest between the set and its drops');
    await _skipRest(h);
    await _complete(h, w1);
    expect(_resting(), isFalse, reason: 'next set is a drop: no rest');
    await _complete(h, d1);
    expect(_resting(), isFalse);
    await _complete(h, d2);
    expect(_resting(), isTrue, reason: 'rest after the last drop');
    await _skipRest(h);
    await _tapClear(h, find.byKey(ValueKey('more-drop-${d2.id}')));
    sets = (await tester.runAsync(() => _sets(h, fly.id)))!;
    expect(sets.where((s) => s.kind == SetKind.drop), hasLength(3), reason: 'ANOTHER DROP');

    debugPrint('STEP myo-rep cycle: 5 s rest before it');
    final w2 = sets.where((s) => s.isWorkingSet).elementAt(1);
    await _setMenu(h, w2, 'follow-myo');
    sets = (await tester.runAsync(() => _sets(h, fly.id)))!;
    final myo = sets.firstWhere((s) => s.kind == SetKind.myo);
    expect(myo.weight, w2.weight);
    expect(myo.reps, myoRepsPerCycle);
    await _complete(h, w2);
    expect(find.textContaining('REST 0:0'), findsOneWidget, reason: '5 s myo rest');
    await _skipRest(h);
    await _complete(h, myo);
    await _skipRest(h);
    await _tapClear(h, find.byKey(ValueKey('more-myo-${myo.id}')));
    sets = (await tester.runAsync(() => _sets(h, fly.id)))!;
    expect(sets.where((s) => s.kind == SetKind.myo), hasLength(2), reason: 'ANOTHER CYCLE');

    debugPrint('STEP static hold on the next exercise');
    final second = exs[1];
    var sets2 = (await tester.runAsync(() => _sets(h, second.id)))!;
    final last2 = sets2.lastWhere((s) => s.isWorkingSet);
    await _setMenu(h, last2, 'follow-hold');
    sets2 = (await tester.runAsync(() => _sets(h, second.id)))!;
    final hold = sets2.firstWhere((s) => s.kind == SetKind.hold);
    await h.waitFor(find.descendant(of: find.byKey(ValueKey('cell-reps-${hold.id}')), matching: find.text('${holdSeconds}s')), reason: 'hold in seconds');
    await h.shot('myo-and-hold');

    debugPrint('STEP the program drop-set technique pre-creates two 25 % drops');
    final first2 = sets2.firstWhere((s) => s.isWorkingSet);
    await h.tap(find.byKey(ValueKey('set-label-${first2.id}')));
    await h.tap(find.byKey(const ValueKey('technique-$dropTechnique')));
    sets2 = (await tester.runAsync(() => _sets(h, second.id)))!;
    final j = sets2.indexWhere((s) => s.id == first2.id);
    expect(sets2[j].technique, dropTechnique);
    expect([sets2[j + 1].kind, sets2[j + 2].kind], [SetKind.drop, SetKind.drop]);
    expect(sets2[j + 1].weight, lessThan(first2.weight == 0 ? 1 : first2.weight));

    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Superset made in the routine editor: A1/A2 labels, sets alternate, rest after the round', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Push'));
    final push = (await tester.runAsync(() => (h.db!.select(h.db!.routines)..where((t) => t.name.equals('Push'))).getSingle()))!;
    final rows = (await tester.runAsync(() => (h.db!.select(h.db!.routineExercises)
          ..where((t) => t.routineId.equals(push.id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get()))!;

    debugPrint('STEP link rows 1 and 2');
    await h.tap(find.text('Push'));
    await h.tap(find.byKey(ValueKey('link-${rows[0].id}')));
    await h.waitFor(find.byKey(ValueKey('routine-superset-${rows[1].id}')), reason: 'superset bar on both rows');
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
    await h.shot('routine-superset');
    await tester.pageBack();
    await h.settle();

    debugPrint('STEP start: A1/A2 in the workout');
    await h.scrollToTop();
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.text('High-to-Low Cable Fly'));
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
    final exs = (await tester.runAsync(() => _exercises(h)))!;
    expect(exs[0].supersetGroup, isNotNull);
    expect(exs[0].supersetGroup, exs[1].supersetGroup);
    await h.shot('superset-workout');

    debugPrint('STEP A1 set 1 → no rest; A2 set 1 → rest (longest of the two)');
    final a = (await tester.runAsync(() => _sets(h, exs[0].id)))!.firstWhere((s) => s.isWorkingSet);
    final b = (await tester.runAsync(() => _sets(h, exs[1].id)))!.firstWhere((s) => s.isWorkingSet);
    await _complete(h, a);
    expect(_resting(), isFalse, reason: 'go straight to the partner');
    await _complete(h, b);
    expect(_resting(), isTrue, reason: 'rest after the round');
    final longest = exs[0].restSeconds > exs[1].restSeconds ? exs[0].restSeconds : exs[1].restSeconds;
    final shown = find.textContaining('REST ').evaluate().map((e) => (e.widget as Text).data ?? '').first;
    final m = RegExp(r'(\d+):(\d\d)').firstMatch(shown)!;
    final secs = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    expect(secs, inInclusiveRange(longest - 5, longest));

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
