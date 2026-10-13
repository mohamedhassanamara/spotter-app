import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/workout/presentation/exercise_block.dart';

import 'harness.dart';

/// Types [value] on the custom keypad, key by key.
Future<void> typeOnKeypad(AppHarness h, String value) async {
  for (final c in value.split('')) {
    await h.tester.tap(find.byKey(ValueKey(c == '.' ? 'key-dot' : 'key-$c')));
    await h.tester.pump(const Duration(milliseconds: 30));
  }
  await h.settle(2);
}

Future<void> openCell(AppHarness h, WorkoutSet s, String field) async {
  await h.tap(find.byKey(ValueKey('cell-$field-${s.id}')));
  await h.waitFor(find.byKey(const ValueKey('workout-keypad')), scroll: false);
}

Future<void> checkSet(AppHarness h, WorkoutSet s) =>
    h.tap(find.descendant(of: find.byKey(ValueKey('set-${s.id}')), matching: find.byTooltip('Complete set')));

Future<WorkoutSet> setRow(AppHarness h, int id) async =>
    (await h.tester.runAsync(() => (h.db!.select(h.db!.workoutSets)..where((t) => t.id.equals(id))).getSingle()))!;

/// Working sets of the active session, by exercise display name, in order.
Future<Map<String, List<WorkoutSet>>> activeSets(AppHarness h) async {
  final db = h.db!;
  final session = (await h.tester.runAsync(() => (db.select(db.sessions)..where((t) => t.status.equals('active'))).getSingle()))!;
  final exs = (await h.tester.runAsync(() => (db.select(db.sessionExercises)
        ..where((t) => t.sessionId.equals(session.id))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .get()))!;
  final out = <String, List<WorkoutSet>>{};
  for (final e in exs) {
    final sets = (await h.tester.runAsync(() => (db.select(db.workoutSets)
          ..where((t) => t.sessionExerciseId.equals(e.id) & t.isWarmup.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get()))!;
    out[e.displayName!] = sets;
  }
  return out;
}

Future<void> startPush(AppHarness h) async {
  await h.goTab(Icons.fitness_center_outlined);
  await h.waitFor(find.text('Push'));
  await h.tap(find.text('Start').at(2));
  await h.waitFor(find.text('High-to-Low Cable Fly'), reason: 'Push opened');
}

Finder blockOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(ExerciseBlock)).first;

