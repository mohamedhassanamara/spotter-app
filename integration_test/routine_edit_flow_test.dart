import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/workout/presentation/exercise_block.dart';

import 'harness.dart';

Finder _block(String name) => find.ancestor(of: find.text(name), matching: find.byType(ExerciseBlock)).first;

Future<List<SessionExercise>> _sessionExercises(AppHarness h) async {
  final db = h.db!;
  final session = await (db.select(db.sessions)..where((t) => t.status.equals('active'))).getSingle();
  return (db.select(db.sessionExercises)
        ..where((t) => t.sessionId.equals(session.id))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .get();
}

Future<Routine> _routine(AppHarness h, String name) =>
    (h.db!.select(h.db!.routines)..where((t) => t.name.equals(name))).getSingle();

Future<List<RoutineExercise>> _routineRows(AppHarness h, int id) => (h.db!.select(h.db!.routineExercises)
      ..where((t) => t.routineId.equals(id))
      ..orderBy([(t) => OrderingTerm.asc(t.position)]))
    .get();

Future<void> _menu(AppHarness h, SessionExercise ex, String item) async {
  await h.scrollToTop(); // lists build lazily: start from the top, waitFor scrolls down from there
  await h.tap(find.byKey(ValueKey('menu-${ex.id}')));
  await h.tap(find.text(item).last);
}

Future<void> _pickFromLibrary(AppHarness h, String query, String name) async {
  await h.waitFor(find.byType(TextField), scroll: false);
  await h.tester.enterText(find.byType(TextField).first, query);
  await h.settle(6);
  await h.waitFor(find.text(name), reason: '$name in the results');
  await h.tap(find.text(name).first);
}

Future<void> _completeFirstOpenSet(AppHarness h) async {
  final db = h.db!;
  await h.scrollToTop();
  final exs = (await h.tester.runAsync(() => _sessionExercises(h)))!;
  for (final e in exs) {
    final sets = (await h.tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.equals(e.id))).get()))!;
    final open = sets.where((s) => !s.isWarmup && !s.completed).firstOrNull;
    if (open == null) continue;
    await h.tap(find.descendant(of: find.byKey(ValueKey('set-${open.id}')), matching: find.byTooltip('Complete set')));
    if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    return;
  }
}

Future<void> _finishTo(AppHarness h, {required bool expectRoutineDialog, bool update = true}) async {
  await h.scrollToTop();
  await h.tap(find.text('Finish'));
  if (find.text('Finish workout?').evaluate().isNotEmpty) {
    await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finish')));
  }
  if (expectRoutineDialog) {
    await h.waitFor(find.text('Update routine?'), scroll: false, reason: 'session differs from the routine');
    await h.shot('routine-update-dialog');
    await h.tap(find.byKey(ValueKey(update ? 'update-routine' : 'keep-routine')));
  } else {
    expect(find.text('Update routine?'), findsNothing);
  }
  await h.waitForSummary(reason: 'summary');
  await h.leaveSummary();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Mid-workout edits (replace from program subs, remove, add, reorder, sets, target reps) → Update routine; '
      'routine editor override and Reset to program', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Push'));
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.text('High-to-Low Cable Fly'), reason: 'Push opened');
    final push = (await tester.runAsync(() => _routine(h, 'Push')))!;
    final before = (await tester.runAsync(() => _routineRows(h, push.id)))!;
    var exs = (await tester.runAsync(() => _sessionExercises(h)))!;
    expect(exs.map((e) => e.routineExerciseId), before.map((r) => r.id), reason: 'session rows link to routine rows');

    debugPrint('STEP replace: the program substitutions are listed first');
    final first = exs.first;
    await _menu(h, first, 'Replace');
    await h.waitFor(find.text('Search the library'), scroll: false);
    final subs = find.byIcon(Icons.swap_horiz_rounded);
    expect(subs, findsWidgets, reason: 'substitutions offered');
    await h.shot('replace-sheet');
    // First substitution that resolves to a library exercise.
    final tiles = find.ancestor(of: subs, matching: find.byType(ListTile));
    final enabled = tiles.evaluate().map((e) => e.widget as ListTile).toList().indexWhere((t) => t.enabled && t.onTap != null);
    expect(enabled, isNonNegative, reason: 'at least one substitution is in the library');
    await h.tap(tiles.at(enabled));
    exs = (await tester.runAsync(() => _sessionExercises(h)))!;
    expect(exs.first.exerciseId, isNot(first.exerciseId));
    expect(exs.first.routineExerciseId, before.first.id, reason: 'the replacement keeps the routine row');

    debugPrint('STEP remove the last exercise');
    final last = exs.last;
    await _menu(h, last, 'Remove');
    await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Remove')));

    debugPrint('STEP target reps');
    exs = (await tester.runAsync(() => _sessionExercises(h)))!;
    final second = exs[1];
    await _menu(h, second, 'Target reps');
    await h.waitFor(find.byKey(const ValueKey('target-max')), scroll: false);
    await h.tap(find.descendant(of: find.byKey(const ValueKey('target-max')), matching: find.byIcon(Icons.add_rounded)));
    await h.tap(find.byKey(const ValueKey('target-save')));
    final edited = (await tester.runAsync(() => _sessionExercises(h)))![1];
    expect(edited.targetsEdited, isTrue);
    expect(edited.repMax, second.repMax + 1);

    debugPrint('STEP add a set');
    await h.tap(find.descendant(of: _block(edited.displayName!), matching: find.text('ADD SET')));

    debugPrint('STEP reorder: move the second exercise up, then the reorder sheet');
    await _menu(h, edited, 'Move up');
    await _menu(h, edited, 'Reorder exercises');
    await h.waitFor(find.byKey(const ValueKey('reorder-done')), scroll: false);
    await h.shot('reorder-sheet');
    await h.tap(find.byKey(const ValueKey('reorder-done')));
    exs = (await tester.runAsync(() => _sessionExercises(h)))!;
    expect(exs.first.id, edited.id);

    debugPrint('STEP add an exercise from the library');
    await h.tap(find.text('Add exercise'));
    await _pickFromLibrary(h, 'hammer', 'Hammer Curls');
    await h.waitFor(find.text('Hammer Curls'), reason: 'added mid-workout');

    await _completeFirstOpenSet(h);
    exs = (await tester.runAsync(() => _sessionExercises(h)))!;
    await _finishTo(h, expectRoutineDialog: true);

    final after = (await tester.runAsync(() => _routineRows(h, push.id)))!;
    expect(after.map((r) => r.exerciseId), exs.map((e) => e.exerciseId), reason: 'routine follows the session');
    expect(after.any((r) => r.exerciseId == last.exerciseId && r.id == before.last.id), isFalse, reason: 'removed row deleted');
    final target = after.firstWhere((r) => r.id == edited.routineExerciseId);
    expect((target.overrideRepMin, target.overrideRepMax), (edited.repMin, edited.repMax));
    expect(target.targetSets, before.firstWhere((r) => r.id == edited.routineExerciseId).targetSets + 1);
    expect(after.firstWhere((r) => r.id == before.first.id).programRelation, anyOf('substitution', 'swap'));

    debugPrint('STEP routine editor: override sets/reps, then Reset to program');
    await h.goTab(Icons.fitness_center_outlined);
    await h.tap(find.text('Push'));
    final editorName = target.displayName!;
    await h.waitFor(find.text(editorName));
    await h.waitFor(find.textContaining('your rep range'), reason: 'override shown on the row');
    await h.tap(find.byKey(ValueKey('edit-${target.id}'))); // the sliders button edits; tapping the row opens the exercise page
    await h.waitFor(find.byKey(const ValueKey('reset-to-program')), scroll: false);
    await h.shot('routine-override-sheet');
    await h.tap(find.descendant(of: find.byKey(const ValueKey('override-sets')), matching: find.byIcon(Icons.add_rounded)));
    await h.tap(find.byKey(const ValueKey('override-save')));
    var row = (await tester.runAsync(() => _routineRows(h, push.id)))!.firstWhere((r) => r.id == target.id);
    expect(row.targetSets, target.targetSets + 1);

    await h.tap(find.byKey(ValueKey('edit-${target.id}')));
    await h.tap(find.byKey(const ValueKey('reset-to-program')));
    row = (await tester.runAsync(() => _routineRows(h, push.id)))!.firstWhere((r) => r.id == target.id);
    expect(row.overrideRepMin, isNull);
    expect(row.targetSets, before.firstWhere((r) => r.id == target.id).targetSets, reason: 'program set count restored');
    expect(find.textContaining('your rep range'), findsNothing);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });

  testWidgets('Keep routine as is leaves the routine untouched; empty workout works', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Push'));
    final push = (await tester.runAsync(() => _routine(h, 'Push')))!;
    final before = (await tester.runAsync(() => _routineRows(h, push.id)))!;
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.text('High-to-Low Cable Fly'));
    final exs = (await tester.runAsync(() => _sessionExercises(h)))!;
    await _menu(h, exs.last, 'Remove');
    await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Remove')));
    await _completeFirstOpenSet(h);
    await _finishTo(h, expectRoutineDialog: true, update: false);
    final after = (await tester.runAsync(() => _routineRows(h, push.id)))!;
    expect(after.map((r) => (r.id, r.exerciseId, r.targetSets)), before.map((r) => (r.id, r.exerciseId, r.targetSets)));

    debugPrint('STEP empty workout');
    await h.goTab(Icons.fitness_center_outlined);
    await h.scrollToTop();
    await h.tap(find.text('Start empty workout'));
    await h.waitFor(find.text('Empty workout. Add your first exercise.'));
    await h.tap(find.text('Add exercise'));
    await _pickFromLibrary(h, 'barbell cur', 'Barbell Curl');
    await h.waitFor(find.text('Barbell Curl'));
    await _completeFirstOpenSet(h);
    await _finishTo(h, expectRoutineDialog: false);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
