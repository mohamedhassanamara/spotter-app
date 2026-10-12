import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_providers.dart';

import 'features/debug/presentation/badge_gallery_screen.dart';
import 'features/debug/presentation/debug_menu_screen.dart';
import 'features/debug/presentation/media_matching_screen.dart';
import 'features/debug/presentation/summary_preview.dart';
import 'features/history/presentation/exercise_history_screen.dart';
import 'features/history/presentation/session_detail_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/library/presentation/custom_exercise_screen.dart';
import 'features/library/presentation/exercise_detail_screen.dart';
import 'features/library/presentation/library_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/ranks/presentation/rank_up_screen.dart';
import 'features/ranks/presentation/progress_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/workout/presentation/active_workout_screen.dart';
import 'features/workout/presentation/routine_editor_screen.dart';
import 'features/workout/presentation/summary_screen.dart';
import 'features/workout/presentation/train_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

abstract final class Routes {
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const train = '/train';
  static const library = '/library';
  static const progress = '/progress';
  static const profile = '/profile';
  static const workout = '/workout';
  static const summary = '/summary';
  static const rankUp = '/rank-up';
  static const badgeGallery = '/settings/debug/badges';
  static const mediaMatching = '/settings/debug/media';
  static const pickExercise = '/pick-exercise';
  static const newExercise = '/exercise-new';
  static const settings = '/settings';
  static const debug = '/settings/debug';

  static String routine(int id) => '/routine/$id';
  static String exercise(String id) => '/exercise/${Uri.encodeComponent(id)}';
  static String exerciseHistory(String id) => '/exercise/${Uri.encodeComponent(id)}/history';
  static String editExercise(String id) => '/exercise/${Uri.encodeComponent(id)}/edit';
  static String session(int id) => '/session/$id';
}

GoRouter buildRouter(ValueListenable<bool> onboarded) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    refreshListenable: onboarded,
    redirect: (context, state) {
      final atOnboarding = state.matchedLocation == Routes.onboarding;
      if (!onboarded.value && !atOnboarding) return Routes.onboarding;
      if (onboarded.value && atOnboarding) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.train, builder: (_, _) => const TrainScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.library, builder: (_, _) => const LibraryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.progress, builder: (_, s) => ProgressScreen.fromQuery(s.uri.queryParameters))]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      GoRoute(
        path: Routes.workout,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const ActiveWorkoutScreen(),
      ),
      GoRoute(
        path: Routes.rankUp,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, _) => CustomTransitionPage<void>(
          child: Consumer(
            builder: (context, ref, _) => RankUpScreen(
              changes: ref.read(lastSummaryProvider)?.rankUps ?? const [],
              onDone: () => context.pushReplacement(Routes.summary),
            ),
          ),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        ),
      ),
      GoRoute(
        path: Routes.summary,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const SummaryScreen(),
      ),
      GoRoute(
        path: Routes.pickExercise,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const LibraryScreen(pickMode: true),
      ),
      GoRoute(
        path: Routes.newExercise,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const CustomExerciseScreen(),
      ),
      GoRoute(
        path: '/routine/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => RoutineEditorScreen(routineId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/exercise/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => ExerciseDetailScreen(exerciseId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'history',
            parentNavigatorKey: rootNavigatorKey,
            builder: (_, s) => ExerciseHistoryScreen(exerciseId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'edit',
            parentNavigatorKey: rootNavigatorKey,
            builder: (_, s) => CustomExerciseScreen(editId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/session/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => SessionDetailScreen(sessionId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const SettingsScreen(),
        routes: [
          if (kDebugMode)
            GoRoute(
              path: 'debug',
              parentNavigatorKey: rootNavigatorKey,
              builder: (_, _) => const DebugMenuScreen(),
              routes: [
                GoRoute(path: 'badges', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const BadgeGalleryScreen()),
                GoRoute(path: 'media', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const MediaMatchingScreen()),
                GoRoute(path: 'summary-preview', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const SummaryPreviewScreen()),
                GoRoute(
                  path: 'rank-up-preview',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, _) => RankUpScreen(changes: demoRankUps(), onDone: () {}, loop: true),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Train'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Progress'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}
