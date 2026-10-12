import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/domain/equipment.dart';
import '../../../core/domain/training.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart' show formatKg;
import '../../export/data/export_service.dart';
import '../../tutorials/presentation/tutorial_video.dart';
import '../../program/data/program_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(currentSettingsProvider);
    final ctrl = ref.read(settingsControllerProvider);
    final bw = ref.watch(latestBodyWeightProvider).value;
    final health = ref.watch(healthSourceProvider);
    final sync = ref.watch(healthSyncProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          const SectionHeader('Training'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _CounterTile(
                title: 'Weekly goal',
                subtitle: 'Sessions per week for the streak',
                value: '${s.weeklyGoal}',
                onMinus: s.weeklyGoal > 1 ? () => ctrl.setWeeklyGoal(s.weeklyGoal - 1) : null,
                onPlus: s.weeklyGoal < 14 ? () => ctrl.setWeeklyGoal(s.weeklyGoal + 1) : null,
              ),
              ListTile(
                title: const Text('Compound rep range'),
                subtitle: const Text('Default for new routine exercises'),
                trailing: Text('${s.compoundRange}', style: _valueStyle),
                onTap: () async {
                  final r = await _editRange(context, 'Compound rep range', s.compoundRange);
                  if (r != null) await ctrl.setCompoundRange(r);
                },
              ),
              ListTile(
                title: const Text('Isolation rep range'),
                subtitle: const Text('Default for new routine exercises'),
                trailing: Text('${s.isolationRange}', style: _valueStyle),
                onTap: () async {
                  final r = await _editRange(context, 'Isolation rep range', s.isolationRange);
                  if (r != null) await ctrl.setIsolationRange(r);
                },
              ),
              _CounterTile(
                title: 'Target reps in reserve',
                subtitle: 'Default RIR for new routine exercises',
                value: '${s.defaultRir}',
                onMinus: s.defaultRir > 0 ? () => ctrl.setDefaultRir(s.defaultRir - 1) : null,
                onPlus: s.defaultRir < 5 ? () => ctrl.setDefaultRir(s.defaultRir + 1) : null,
              ),
              ListTile(
                title: const Text('Rest after compounds'),
                trailing: Text(formatClock(Duration(seconds: s.defaultRestCompound)), style: _valueStyle),
                onTap: () async {
                  final v = await promptNumber(context, title: 'Rest after compounds', initial: s.defaultRestCompound.toDouble(), suffix: 's', decimal: false);
                  if (v != null && v >= 15 && v <= 900) await ctrl.setRestCompound(v.round());
                },
              ),
              ListTile(
                title: const Text('Rest after isolations'),
                trailing: Text(formatClock(Duration(seconds: s.defaultRestIsolation)), style: _valueStyle),
                onTap: () async {
                  final v = await promptNumber(context, title: 'Rest after isolations', initial: s.defaultRestIsolation.toDouble(), suffix: 's', decimal: false);
                  if (v != null && v >= 15 && v <= 900) await ctrl.setRestIsolation(v.round());
                },
              ),
            ]),
          ),
          const SectionHeader('Equipment increments'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final kind in EquipmentKind.values)
                ListTile(
                  title: Text(kind.label),
                  trailing: Text('${formatKg(s.increments.of(kind))} kg', style: _valueStyle),
                  onTap: () async {
                    final v = await promptNumber(context, title: '${kind.label} increment', initial: s.increments.of(kind), suffix: 'kg');
                    if (v == null) return;
                    if (v <= 0 || v > 50) {
                      if (context.mounted) _snack(context, 'Increment must be between 0 and 50 kg');
                      return;
                    }
                    await ctrl.setIncrement(s.increments, kind, v);
                  },
                ),
            ]),
          ),
          const SectionHeader('Body'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.monitor_weight_outlined),
              title: const Text('Bodyweight'),
              subtitle: Text(bw == null
                  ? 'Not set: needed for ranks'
                  : '${bw.source == 'health' ? 'From Apple Health' : 'Entered manually'} · ${DateFormat.yMMMd().format(bw.measuredAt)}'),
              trailing: Text(bw == null ? 'Set' : '${formatKg(bw.kg)} kg', style: _valueStyle),
              onTap: () async {
                final v = await promptNumber(context, title: 'Bodyweight', initial: bw?.kg, suffix: 'kg');
                if (v == null) return;
                if (v < 30 || v > 300) {
                  if (context.mounted) _snack(context, 'Enter a bodyweight between 30 and 300 kg');
                  return;
                }
                await ref.read(bodyWeightRepositoryProvider).addManual(v);
              },
            ),
          ),
          const SectionHeader('Apple Health'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              ListTile(
                leading: Icon(Icons.favorite_rounded, color: health.isFake ? AppColors.warning : AppColors.danger),
                title: Text(health.name),
                subtitle: Text(_syncText(sync)),
                trailing: sync.syncing ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : null,
              ),
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Sync now'),
                onTap: sync.syncing ? null : () => ref.read(healthSyncProvider.notifier).sync(),
              ),
              ListTile(
                leading: const Icon(Icons.lock_open_rounded),
                title: const Text('Request permissions again'),
                subtitle: const Text('If you denied access, change it in the Health app under Sharing → Apps → Spotter.'),
                onTap: () async {
                  final ok = await ref.read(healthSourceProvider).requestPermissions();
                  await ctrl.setHealthRequested(true);
                  await ref.read(healthSyncProvider.notifier).sync();
                  if (context.mounted && !ok) _snack(context, 'Apple Health is not available on this device');
                },
              ),
            ]),
          ),
          const SectionHeader('Notifications'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Enable rest-timer alerts'),
              subtitle: const Text('An alert when rest is over, even with the phone locked'),
              onTap: () async {
                final ok = await ref.read(notificationServiceProvider).requestPermission();
                if (context.mounted) {
                  _snack(context, ok ? 'Rest-timer alerts enabled' : 'Notifications are off. Enable them in iOS Settings → Spotter.');
                }
              },
            ),
          ),
          const SectionHeader('Program'),
          const AppCard(padding: EdgeInsets.symmetric(vertical: 4), child: _ProgramTiles()),
          const SectionHeader('Tutorials'),
          const AppCard(padding: EdgeInsets.symmetric(vertical: 4), child: _YouTubeKeyTile()),
          const SectionHeader('Import'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Import from Liftoff'),
              subtitle: const Text('Workout history from a Liftoff CSV export'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.importLiftoff),
            ),
          ),
          const SectionHeader('Export'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'All sessions, sets and readiness days, with ISO timestamps and a schema_version.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _ExportButton(label: 'Export JSON', icon: Icons.data_object_rounded, csv: false)),
                  const SizedBox(width: 12),
                  Expanded(child: _ExportButton(label: 'Export CSV', icon: Icons.table_chart_outlined, csv: true)),
                ]),
              ],
            ),
          ),
          const SectionHeader('About'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Spotter 1.0.0'),
                subtitle: const Text('All data stays on this iPhone. Exercise data: free-exercise-db (public domain). '
                    'Long-press for the error log.'),
                // Release builds too: the error log is how bugs get reported from the phone.
                onLongPress: () => context.push(Routes.errorLog),
              ),
              if (kDebugMode)
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined, color: AppColors.warning),
                  title: const Text('Debug menu'),
                  subtitle: const Text('Seed data, fake Health toggle (debug builds only)'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.debug),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  static const _valueStyle = TextStyle(fontWeight: FontWeight.w800, fontSize: 16);

  static String _syncText(HealthSyncState s) {
    if (s.syncing) return 'Syncing…';
    if (s.error != null) return 'Last sync failed: ${s.error}';
    final r = s.lastResult;
    if (r == null || s.lastSync == null) return 'Not synced yet this session';
    final when = DateFormat.Hm().format(s.lastSync!);
    return 'Synced at $when · ${r.daysWithData}/${r.days} days with data'
        '${r.bodyMass == null ? ' · no body mass' : ' · body mass ${formatKg(r.bodyMass!.kg)} kg'}';
  }

  static void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  static Future<RepRange?> _editRange(BuildContext context, String title, RepRange current) {
    var min = current.min, max = current.max;
    return showDialog<RepRange>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _CounterTile(
              title: 'Minimum',
              value: '$min',
              onMinus: min > 1 ? () => setState(() => min--) : null,
              onPlus: min < max ? () => setState(() => min++) : null,
            ),
            _CounterTile(
              title: 'Maximum',
              value: '$max',
              onMinus: max > min ? () => setState(() => max--) : null,
              onPlus: max < 30 ? () => setState(() => max++) : null,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(RepRange(min, max)), child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}

class _YouTubeKeyTile extends ConsumerWidget {
  const _YouTubeKeyTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ref.watch(youtubeKeyProvider).value;
    final masked = key == null ? 'Not set: paste YouTube links to pin tutorials' : 'Set (…${key.substring(key.length - 4)}). Stored in the iOS Keychain';
    return ListTile(
      leading: const Icon(Icons.smart_display_outlined),
      title: const Text('YouTube Data API key (optional)'),
      subtitle: Text(masked),
      trailing: key == null ? const Icon(Icons.chevron_right_rounded) : const Icon(Icons.check_circle_rounded, color: AppColors.primary),
      onTap: () async {
        final value = await promptText(context, title: 'YouTube Data API key', initial: key ?? '', hint: 'AIza… (leave empty to remove)');
        if (value == null) return;
        await ref.read(youtubeKeyStoreProvider).write(value);
        ref.invalidate(youtubeKeyProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(value.trim().isEmpty ? 'API key removed' : 'API key saved to the Keychain')),
          );
        }
      },
    );
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({required this.title, this.subtitle, required this.value, required this.onMinus, required this.onPlus});
  final String title;
  final String? subtitle;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(iconSize: 28, onPressed: onMinus, icon: const Icon(Icons.remove_circle_outline_rounded)),
        SizedBox(width: 28, child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
        IconButton(iconSize: 28, onPressed: onPlus, icon: const Icon(Icons.add_circle_outline_rounded)),
      ]),
    );
  }
}

class _ExportButton extends ConsumerStatefulWidget {
  const _ExportButton({required this.label, required this.icon, required this.csv});
  final String label;
  final IconData icon;
  final bool csv;

  @override
  ConsumerState<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<_ExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      await ref.read(exportServiceProvider).share(csv: widget.csv, origin: origin);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _export,
      icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(widget.icon),
      label: Text(widget.label),
    );
  }
}

class _ProgramTiles extends ConsumerWidget {
  const _ProgramTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program = ref.watch(programProvider).value;
    return Column(children: [
      ListTile(
        leading: const Icon(Icons.calendar_view_week_rounded),
        title: Text(program?.name ?? 'Program'),
        subtitle: const Text('Standard hard-week targets every session (no week plan). '
            'Planned rest: Wednesday and Sunday.'),
      ),
      ListTile(
        leading: const Icon(Icons.restart_alt_rounded),
        title: const Text('Reinstall my Min-Max routines'),
        subtitle: const Text('Replaces all routines with the five program routines (history is kept)'),
        onTap: () async {
          final ok = await confirm(context,
              title: 'Replace routines?', message: 'All routines will be replaced by your five Min-Max Phase 2 routines.', action: 'Replace');
          if (!ok || program == null) return;
          final skipped = await ref.read(programRepositoryProvider).installMyRoutines(
                program: program,
                definition: await ProgramRepository.loadMyRoutines(),
                catalog: await ref.read(catalogProvider.future),
                settings: ref.read(currentSettingsProvider),
                now: ref.read(clockProvider)(),
              );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(skipped.isEmpty ? 'Routines installed' : 'Installed; skipped: ${skipped.join(', ')}'),
            ));
          }
        },
      ),
    ]);
  }

}
