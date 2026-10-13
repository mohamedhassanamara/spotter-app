import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/app_providers.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/core/domain/history.dart';
import 'package:spotter/core/notifications/notification_service.dart';
import 'package:spotter/core/theme/app_theme.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/workout/data/session_repository.dart';
import 'package:spotter/features/workout/presentation/active_workout_screen.dart';

class _QuietNotifications extends NotificationService {
  final scheduled = <DateTime>[];
  @override
  Future<void> init() async {}
  @override
  Future<void> scheduleRestDone(DateTime at, {String body = ''}) async => scheduled.add(at);
  @override
  Future<void> cancelRest() async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime(2026, 10, 12, 18);

  Future<(AppDatabase, _QuietNotifications)> setUpSession(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final notifications = _QuietNotifications();
    await tester.runAsync(() async {
      final ex = ExerciseRepository(db);
      await ex.ensureSeeded(jsonOverride: File('assets/exercises.json').readAsStringSync());
      final catalog = await ex.watchCatalog().first;
      final sessions = SessionRepository(db);
      final id = await sessions.start(
        name: 'Push A',
        coach: CoachContext(
          history: TrainingHistory.empty,
          readiness: null,
          overloaded: const {},
          freezes: const {},
          increments: Increments.defaults,
          now: now,
        ),
        catalog: catalog,
      );
      await sessions.addExercise(
        sessionId: id,
        info: catalog['Barbell_Curl']!,
        range: const RepRange(8, 12),
        targetSets: 2,
        restSeconds: 90,
        targetRir: 2,
        coach: CoachContext(
          history: TrainingHistory.empty,
          readiness: null,
          overloaded: const {},
          freezes: const {},
          increments: Increments.defaults,
          now: now,
        ),
      );
    });
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notifications),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const ActiveWorkoutScreen()),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (db, notifications);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('✓ on an untouched row logs the suggestion; rest shows in the header, not full screen', (tester) async {
    final (db, notifications) = await setUpSession(tester);
    expect(find.text('Barbell Curl'), findsOneWidget);
    expect(find.byTooltip('Complete set'), findsNWidgets(2));
    final before = await tester.runAsync(() => db.select(db.workoutSets).get());

    await tester.tap(find.byTooltip('Complete set').first);
    await settle(tester);

    final sets = await tester.runAsync(() => db.select(db.workoutSets).get());
    final done = sets!.where((s) => s.completed).single;
    expect(done.weight, before!.first.weight);
    expect(done.reps, before.first.reps);
    expect(done.rpe, 8, reason: 'effort pre-filled from the prescription (2 left → RPE 8)');
    expect(notifications.scheduled.single, now.add(const Duration(seconds: 90)));
    expect(find.text('REST 1:30'), findsOneWidget);
    // Unmount first so no provider has a query in flight in the fake-async zone.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('keypad: equipment increment, amber chip over the suggestion, reason only when short of the range', (tester) async {
    final (db, _) = await setUpSession(tester);
    // Calibration sets carry no suggested weight, so give the sets one to test the guardrail.
    late List<WorkoutSet> sets;
    await tester.runAsync(() async {
      sets = await db.select(db.workoutSets).get();
      await (db.update(db.workoutSets)).write(const WorkoutSetsCompanion(suggestedWeight: Value(20), weight: Value(20), suggestedReps: Value(8), reps: Value(8)));
    });
    await settle(tester);

    // KG cell → keypad → + (the next barbell load that exists: 2.5 kg plates, so 5 kg steps) → hide:
    // 25 kg, 25 % over 20.
    await tester.tap(find.byKey(ValueKey('cell-kg-${sets.first.id}')));
    await settle(tester);
    expect(find.byKey(const ValueKey('workout-keypad')), findsOneWidget);
    expect(find.text('+2.5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('key-plus-inc')));
    await tester.tap(find.byKey(const ValueKey('key-hide')));
    await settle(tester);
    expect(find.byKey(const ValueKey('workout-keypad')), findsNothing);
    expect(find.text('+25%'), findsOneWidget);

    // Reps inside the range: logged without any interruption, flagged as an override.
    await tester.tap(find.byTooltip('Complete set').first);
    await settle(tester);
    var rows = await tester.runAsync(() => db.select(db.workoutSets).get());
    expect(rows!.first.completed, isTrue);
    expect(rows.first.isOverride, isTrue);
    expect(rows.first.overrideReason, isNull);

    // Second set: 22.5 kg for 5 reps (below 8): too heavy → the reason sheet.
    await tester.runAsync(() => (db.update(db.workoutSets)..where((t) => t.id.equals(sets[1].id)))
        .write(const WorkoutSetsCompanion(weight: Value(22.5), reps: Value(5))));
    await settle(tester);
    await tester.tap(find.byTooltip('Complete set').last);
    await settle(tester);
    expect(find.text('Heavier than suggested and short of the range'), findsOneWidget);
    await tester.tap(find.text('Felt strong'));
    await settle(tester);
    rows = await tester.runAsync(() => db.select(db.workoutSets).get());
    expect(rows!.last.completed, isTrue);
    expect(rows.last.overrideReason, 'feltStrong');
    // Unmount first so no provider has a query in flight in the fake-async zone.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(db.close);
  });
}
