import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../router.dart';
import '../data/routine_repository.dart';

/// Starts a session (from a routine or empty) and opens the active workout.
/// If a session is already running, it is resumed instead.
Future<void> startWorkout(BuildContext context, WidgetRef ref, {RoutineWithExercises? routine}) async {
  final sessions = ref.read(sessionRepositoryProvider);
  if (await sessions.activeSession() != null) {
    if (context.mounted) context.push(Routes.workout);
    return;
  }
  final catalog = await ref.read(catalogProvider.future);
  final coach = await ref.read(coachContextBuilderProvider)();
  final name = routine?.routine.name ?? '${DateFormat('EEEE').format(coach.now)} workout';
  final program = await ref.read(programProvider.future);
  final week = await ref.read(programWeekProvider.future);
  await sessions.start(name: name, coach: coach, catalog: catalog, routine: routine, program: program, programWeek: week);
  if (context.mounted) context.push(Routes.workout);
}

/// The routine after the one used most recently (cycling), or the first routine.
RoutineWithExercises? nextRoutine(List<RoutineWithExercises> routines, int? lastRoutineId) {
  if (routines.isEmpty) return null;
  final idx = routines.indexWhere((r) => r.routine.id == lastRoutineId);
  if (idx < 0) return routines.first;
  return routines[(idx + 1) % routines.length];
}
