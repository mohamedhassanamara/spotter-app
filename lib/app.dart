import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_providers.dart';
import 'core/diagnostics/error_log.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/keyboard_dismisser.dart';
import 'features/tutorials/presentation/exercise_demo.dart';
import 'features/workout/data/equipment_sync.dart';
import 'features/workout/data/workout_activity_sync.dart';
import 'features/workout/presentation/rest_timer.dart';
import 'router.dart';

class SpotterApp extends ConsumerStatefulWidget {
  const SpotterApp({super.key});

  @override
  ConsumerState<SpotterApp> createState() => _SpotterAppState();
}

class _SpotterAppState extends ConsumerState<SpotterApp> {
  late final AppLifecycleListener _lifecycle;
  final _onboarded = ValueNotifier<bool>(false);
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    ref.listenManual(settingsProvider, (_, next) {
      final v = next.value?.onboarded;
      if (v != null) _onboarded.value = v;
    }, fireImmediately: true);
    // Exercise ↔ ExerciseDB matching and GIF prefetch for routine exercises (re-runs when routines change).
    ref.listenManual(mediaBootstrapProvider, (_, next) {
      if (next.hasError) ErrorLog.instance.recordCaught(next.error!, next.stackTrace ?? StackTrace.current);
    });
    // The streak's last-chance reminder follows the streak and the Settings toggle.
    ref.listenManual(streakReminderProvider, (_, plan) {
      final n = ref.read(notificationServiceProvider);
      _step(() => plan == null ? n.cancelStreakReminder() : n.scheduleStreakReminder(plan.at, body: plan.body));
    }, fireImmediately: true);
    // The workout's Live Activity follows the active session (sets ticked, exercises added) and the rest.
    ref.listenManual(activeSessionProvider, (_, _) => ref.read(workoutActivitySyncProvider).refresh(), fireImmediately: true);
    ref.listenManual(catalogProvider, (_, _) => ref.read(workoutActivitySyncProvider).refresh());
    // A Weight steps change (menu in a workout, or Settings → My gym equipment) re-snaps the running workout's sets that are not done yet.
    ref.listenManual(gymEquipmentProvider, (prev, next) {
      final a = prev?.value, b = next.value;
      if (a == null || b == null || a.encode() == b.encode()) return;
      _step(() => ref.read(equipmentSyncProvider).onGymChanged(b));
    });
    _lifecycle = AppLifecycleListener(onResume: () {
      ref.read(dayTickProvider.notifier).bump();
      _step(() => ref.read(restTimerProvider).resync());
      _refreshHealth();
    });
    // Independent startup steps: one failing must not block the others, and every failure is logged.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _step(() => ref.read(notificationServiceProvider).init());
      _step(_refreshHealth);
      _step(() => ref.read(rankLadderMigrationProvider.future));
    });
  }

  Future<void> _step(Future<Object?> Function() f) async {
    try {
      await f();
    } catch (e, st) {
      // If the app is being torn down, the step was simply cancelled.
      if (mounted) ErrorLog.instance.recordCaught(e, st);
    }
  }

  /// Pulls fresh Health data on launch and whenever the app comes back to the foreground.
  Future<void> _refreshHealth() async {
    final settings = await ref.read(settingsProvider.future);
    if (!settings.onboarded || !settings.healthPermissionsRequested && !settings.useFakeHealth) return;
    await ref.read(healthSyncProvider.notifier).sync();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _onboarded.dispose();
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return settings.when(
      loading: () => MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: Center(child: CircularProgressIndicator()))),
      error: (e, _) => MaterialApp(theme: buildAppTheme(), home: Scaffold(body: Center(child: Text('Failed to open database: $e')))),
      data: (s) {
        if (_router == null) {
          // No listeners yet, so this can't trigger a rebuild; avoids a bounce through /onboarding.
          _onboarded.value = s.onboarded;
          _router = buildRouter(_onboarded);
        }
        return MaterialApp.router(
          title: 'Spotter',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(),
          themeMode: ThemeMode.dark,
          routerConfig: _router,
          builder: (context, child) => KeyboardDismisser(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
