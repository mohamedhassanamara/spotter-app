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
import 'package:spotter/core/widgets/game_ui.dart';
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

  testWidgets('swipe right completes a set and starts the rest timer', (tester) async {
    final (db, notifications) = await setUpSession(tester);
    expect(find.text('Barbell Curl'), findsOneWidget);
    expect(find.textContaining('TARGET'), findsNWidgets(2));
    expect(find.byType(StepperBox), findsNWidgets(4));

    final firstSwipe = find.byType(Dismissible).first;
    await tester.drag(firstSwipe, const Offset(380, 0));
    await settle(tester);

    final sets = await tester.runAsync(() => db.select(db.workoutSets).get());
    expect(sets!.where((s) => s.completed).length, 1);
    expect(notifications.scheduled.single, now.add(const Duration(seconds: 90)));
    await tester.runAsync(db.close);
  });

  testWidgets('steppers use the equipment increment; an override is flagged and not completed by swipe', (tester) async {
    final (db, _) = await setUpSession(tester);
    // Calibration sets carry no suggested weight, so give the first set one to test the guardrail.
    await tester.runAsync(() async {
      final first = (await db.select(db.workoutSets).get()).first;
      await (db.update(db.workoutSets)..where((t) => t.id.equals(first.id)))
          .write(const WorkoutSetsCompanion(suggestedWeight: Value(20), weight: Value(20)));
    });
    await settle(tester);

    // + on the weight stepper: barbell increment 2.5 kg → 22.5 (12.5% over 20).
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await settle(tester);
    expect(find.text('+13% override'), findsOneWidget);

    await tester.drag(find.byType(Dismissible).first, const Offset(380, 0));
    await settle(tester);
    // The set editor opens (RPE + reason required) instead of completing.
    expect(find.textContaining('Why the override?'), findsOneWidget);
    final sets = await tester.runAsync(() => db.select(db.workoutSets).get());
    expect(sets!.first.weight, 22.5);
    expect(sets.where((s) => s.completed), isEmpty);
    await tester.runAsync(db.close);
  });
}
