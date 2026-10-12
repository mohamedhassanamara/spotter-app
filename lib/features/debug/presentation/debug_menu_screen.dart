import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../tutorials/data/edb_v2/edb_budget.dart';
import '../../tutorials/data/edb_v2/edb_client.dart';
import '../../tutorials/data/edb_v2/edb_providers.dart';
import '../data/seed_generator.dart';

final _tableCountsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final db = ref.watch(databaseProvider);
  return {
    'exercises': await db.exercises.count().getSingle(),
    'routines': await db.routines.count().getSingle(),
    'sessions': await db.sessions.count().getSingle(),
    'session_exercises': await db.sessionExercises.count().getSingle(),
    'workout_sets': await db.workoutSets.count().getSingle(),
    'daily_metrics': await db.dailyMetrics.count().getSingle(),
    'body_weights': await db.bodyWeights.count().getSingle(),
    'ego_freezes': await db.egoFreezes.count().getSingle(),
    'xp_events': await db.xpEvents.count().getSingle(),
    'achievements_unlocked': await db.achievementsUnlocked.count().getSingle(),
    'quests': await db.quests.count().getSingle(),
  };
});

/// Hidden developer tools. Only routed in debug builds.
class DebugMenuScreen extends ConsumerStatefulWidget {
  const DebugMenuScreen({super.key});

  @override
  ConsumerState<DebugMenuScreen> createState() => _DebugMenuScreenState();
}

class _DebugMenuScreenState extends ConsumerState<DebugMenuScreen> {
  String? _status;
  bool _busy = false;

  Future<void> _run(String label, Future<String> Function() job) async {
    setState(() {
      _busy = true;
      _status = '$label…';
    });
    try {
      final result = await job();
      if (mounted) setState(() => _status = result);
    } catch (e) {
      if (mounted) setState(() => _status = '$label failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(_tableCountsProvider);
    }
  }

  Future<void> _seed() async {
    final ok = await confirm(
      context,
      title: 'Seed 12 weeks?',
      message: 'This wipes all sessions, routines, XP, achievements, quests, freezes, Health metrics and bodyweights, '
          'then generates 12 weeks of PPL history with fake Health data. The exercise library and settings are kept.',
      action: 'Wipe & seed',
      destructive: true,
    );
    if (!ok) return;
    await _run('Seeding', () async {
      final catalog = await ref.read(catalogProvider.future);
      final settings = ref.read(currentSettingsProvider);
      final report = await SeedGenerator(ref.read(databaseProvider)).seed(
        now: DateTime.now(),
        catalog: catalog,
        settings: settings,
        onProgress: (m) {
          if (mounted) setState(() => _status = m);
        },
      );
      await ref.read(settingsControllerProvider).setOnboarded(true);
      return 'Seeded: $report';
    });
  }

  Future<void> _wipe() async {
    final ok = await confirm(
      context,
      title: 'Wipe training data?',
      message: 'Deletes all sessions, routines, XP, achievements, quests, freezes, Health metrics and bodyweights.',
      action: 'Wipe',
      destructive: true,
    );
    if (!ok) return;
    await _run('Wiping', () async {
      await SeedGenerator(ref.read(databaseProvider)).wipeTrainingData();
      return 'Training data wiped';
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final counts = ref.watch(_tableCountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Debug menu')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppCard(
                borderColor: AppColors.warning,
                child: Row(children: [
                  if (_busy) ...[
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    const SizedBox(width: 12),
                  ],
                  Expanded(child: Text(_status!)),
                ]),
              ),
            ),
          const SectionHeader('Health'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              SwitchListTile(
                title: const Text('Use fake Health data'),
                subtitle: const Text('Deterministic HRV, resting HR, sleep and body mass'),
                value: settings.useFakeHealth,
                onChanged: _busy
                    ? null
                    : (v) => _run('Switching source', () async {
                          await ref.read(settingsControllerProvider).setUseFakeHealth(v);
                          await ref.read(settingsProvider.future);
                          await ref.read(healthSyncProvider.notifier).sync();
                          return v ? 'Fake Health data on and synced' : 'Apple Health on and synced';
                        }),
              ),
              ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Recompute readiness'),
                subtitle: const Text('Re-scores every stored day'),
                onTap: _busy
                    ? null
                    : () => _run('Recomputing', () async {
                          await ref.read(readinessRepositoryProvider).recomputeScores(sinceDays: 365, now: DateTime.now());
                          return 'Readiness recomputed';
                        }),
              ),
              ListTile(
                leading: const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                title: const Text('Error log'),
                subtitle: const Text('Every recorded error, with Copy all'),
                onTap: () => context.push(Routes.errorLog),
              ),
              ListTile(
                leading: const Icon(Icons.view_in_ar_rounded),
                title: const Text('Media matching'),
                subtitle: const Text('Unmatched and low-confidence 3D demos'),
                onTap: () => context.push(Routes.mediaMatching),
              ),
              ListTile(
                leading: const Icon(Icons.shield_rounded),
                title: const Text('Rank badges & rank-up preview'),
                onTap: () => context.push(Routes.badgeGallery),
              ),
            ]),
          ),
          const SectionHeader('ExerciseDB V2'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SwitchListTile(
              key: const ValueKey('use-edb-v2'),
              title: const Text('Use ExerciseDB V2'),
              subtitle: const Text('Off: the app makes zero API calls and uses free sources only'),
              value: ref.watch(edbEnabledProvider).value ?? false,
              onChanged: (v) => ref.read(databaseProvider).putSetting(edbEnabledKey, '$v'),
            ),
          ),
          const SizedBox(height: 8),
          const AppCard(child: _EdbUsage()),
          const SectionHeader('Data'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
                title: const Text('Seed 12 weeks of history'),
                subtitle: const Text('6 sessions/week PPL, progression, override episodes, varied recovery'),
                onTap: _busy ? null : _seed,
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
                title: const Text('Wipe training data'),
                onTap: _busy ? null : _wipe,
              ),
            ]),
          ),
          const SectionHeader('Table row counts'),
          AppCard(
            child: AsyncBody(
              value: counts,
              builder: (m) => Column(children: [
                for (final e in m.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text(e.key, style: const TextStyle(color: AppColors.textSecondary))),
                      Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}


/// API calls this month against the 2,000/month plan, where the figure comes from, and recent calls,
/// fallbacks and errors.
class _EdbUsage extends ConsumerWidget {
  const _EdbUsage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(edbBudgetProvider).value;
    final log = ref.watch(edbLogProvider).value ?? const <EdbLogEntry>[];
    if (b == null) return const SizedBox(height: 40);
    final color = b.stopped ? AppColors.danger : (b.warn ? AppColors.warning : AppColors.primary);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${b.used} / ${EdbBudget.planLimit} calls · ${b.month}', key: const ValueKey('edb-usage'), style: AppType.title.copyWith(color: color)),
      const SizedBox(height: 6),
      ProgressBar(value: (b.used / EdbBudget.planLimit).clamp(0.0, 1.0), color: color),
      const SizedBox(height: 6),
      Text(
        '${b.fromHeaders ? 'From RapidAPI headers' : 'Local count'} · warning at ${EdbBudget.softLimit} · stops at ${EdbBudget.hardLimit}'
        '${b.stopped ? ' · STOPPED until ${b.resumesOn().toIso8601String().substring(0, 10)}' : ''}'
        '${edbApiKey.isEmpty ? ' · no API key in this build' : ''}',
        style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
      ),
      if (log.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final e in log.reversed.take(15))
          Text('${e.at.toIso8601String().substring(5, 16)}  ${e.kind}  ${e.detail}',
              style: AppType.bodyS.copyWith(fontSize: 11, color: e.kind == 'call' ? AppColors.textSecondary : AppColors.warning)),
      ],
    ]);
  }
}
