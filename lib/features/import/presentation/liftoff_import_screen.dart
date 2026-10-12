import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../data/liftoff_import_service.dart';
import '../domain/liftoff_mapping.dart';

/// The picked CSV's text, or null when the picker was cancelled. Integration tests replace it with
/// a fixture, since the iOS document picker can't be driven from a test.
final liftoffCsvSourceProvider = Provider<Future<String?> Function()>((ref) => () async {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
      if (files.isEmpty) return null;
      return utf8.decode(await files.first.readAsBytes(), allowMalformed: true);
    });

final liftoffImportServiceProvider = Provider((ref) => LiftoffImportService(ref.watch(databaseProvider)));

/// Settings → Import from Liftoff: pick the export, preview what would be imported (sessions, sets,
/// dates, every name mapping), fix unsure names, confirm.
class LiftoffImportScreen extends ConsumerStatefulWidget {
  const LiftoffImportScreen({super.key});

  @override
  ConsumerState<LiftoffImportScreen> createState() => _LiftoffImportScreenState();
}

class _LiftoffImportScreenState extends ConsumerState<LiftoffImportScreen> {
  String? _csv;
  LiftoffPreview? _preview;
  LiftoffImportResult? _result;
  final Map<String, String> _manual = {};
  bool _busy = false;
  String? _error;
  bool _showAll = false;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final csv = await ref.read(liftoffCsvSourceProvider)();
      if (csv == null) return;
      _csv = csv;
      _manual.clear();
      await _refreshPreview();
    } on FormatException catch (e) {
      _error = e.message;
    } catch (e, st) {
      ErrorLog.instance.recordCaught(e, st);
      _error = 'Could not read that file: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshPreview() async {
    final catalog = await ref.read(catalogProvider.future);
    final p = await ref.read(liftoffImportServiceProvider).preview(_csv!, catalog: catalog, manual: _manual);
    if (mounted) setState(() => _preview = p);
  }

  Future<void> _pickFor(NameMapping m) async {
    final id = await context.push<String>(Routes.pickExercise);
    if (id == null) return;
    _manual[m.liftoffName] = id;
    await _refreshPreview();
  }

  /// Ranks compare lifts to bodyweight. With nothing from Apple Health or onboarding, ask once
  /// rather than assume a number.
  Future<bool> _ensureBodyweight() async {
    if (await ref.read(bodyWeightRepositoryProvider).latest() != null) return true;
    if (!mounted) return false;
    final kg = await promptNumber(
      context,
      title: 'Your bodyweight',
      suffix: 'kg',
      message: 'Apple Health has no weight for you. Ranks compare your lifts to your bodyweight, '
          'so enter it once (you can change it in Settings).',
    );
    if (kg == null || kg < 30 || kg > 300) {
      if (mounted) setState(() => _error = 'Import needs a bodyweight between 30 and 300 kg.');
      return false;
    }
    await ref.read(bodyWeightRepositoryProvider).addManual(kg);
    return true;
  }

  Future<void> _import() async {
    final p = _preview!;
    if (!await _ensureBodyweight()) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(liftoffImportServiceProvider).commit(
            p,
            catalog: await ref.read(catalogProvider.future),
            settings: ref.read(currentSettingsProvider),
            now: ref.read(clockProvider)(),
          );
      if (mounted) setState(() => _result = r);
    } catch (e, st) {
      ErrorLog.instance.recordCaught(e, st);
      if (mounted) setState(() => _error = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Import from Liftoff')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxxl),
        children: [
          if (r != null) ..._done(r) else if (p == null) ..._intro() else ..._previewView(p),
        ],
      ),
    );
  }

  List<Widget> _intro() => [
        const AppCard(
          child: Text(
            'In Liftoff: Settings → Export data → CSV. Save the file to Files, then choose it here. '
            'Nothing is written until you confirm. Re-importing the same file adds only new workouts.',
            style: AppType.body,
          ),
        ),
        const SizedBox(height: Space.l),
        if (_error != null) ...[
          Text(_error!, style: AppType.bodyS.copyWith(color: AppColors.danger)),
          const SizedBox(height: Space.l),
        ],
        BigButton(label: 'Choose CSV file', icon: Icons.upload_file_rounded, busy: _busy, onPressed: _pick),
      ];

  List<Widget> _previewView(LiftoffPreview p) {
    final fmt = DateFormat.yMMMd();
    final review = p.toReview;
    return [
      Row(children: [
        Expanded(child: StatTile(label: 'New sessions', value: '${p.newSessions.length}')),
        const SizedBox(width: Space.m),
        Expanded(child: StatTile(label: 'New sets', value: '${p.newSets}')),
      ]),
      const SizedBox(height: Space.m),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.first == null ? 'No workouts in this file' : '${fmt.format(p.first!)} → ${fmt.format(p.last!)}', style: AppType.title),
          const SizedBox(height: Space.s),
          Text(
            '${p.parse.sessions.length} sessions in the file'
            '${p.alreadyImported > 0 ? ' · ${p.alreadyImported} already imported' : ''}'
            ' · ${p.mappings.length} exercise names'
            '${p.parse.skipped.isNotEmpty ? ' · ${p.parse.skipped.length} rows skipped (cardio, timed or empty)' : ''}',
            style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: Space.s),
          Text(
            'Imported sets count as taken to failure. They feed history, PRs, ranks and suggestions '
            '(from your last 2–3 sessions), not discipline stats or XP.',
            style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
          ),
        ]),
      ),
      if (review.isNotEmpty) ...[
        SectionLabel('Check these (${review.length})'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [for (final m in review) _MappingTile(m, onTap: () => _pickFor(m))]),
        ),
      ],
      SectionLabel('All exercise names (${p.mappings.length})'),
      AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (final m in _showAll ? p.mappings : p.mappings.take(8)) _MappingTile(m, onTap: () => _pickFor(m)),
          if (p.mappings.length > 8)
            TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(_showAll ? 'Show fewer' : 'Show all ${p.mappings.length}'),
            ),
        ]),
      ),
      const SizedBox(height: Space.xl),
      if (_error != null) ...[
        Text(_error!, style: AppType.bodyS.copyWith(color: AppColors.danger)),
        const SizedBox(height: Space.l),
      ],
      BigButton(
        label: p.newSessions.isEmpty ? 'Nothing new to import' : 'Import ${p.newSessions.length} sessions',
        icon: Icons.download_done_rounded,
        busy: _busy,
        onPressed: p.newSessions.isEmpty ? null : _import,
      ),
      const SizedBox(height: Space.m),
      TextButton(onPressed: _busy ? null : _pick, child: const Text('Choose a different file')),
    ];
  }

  List<Widget> _done(LiftoffImportResult r) => [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 40),
            const SizedBox(height: Space.m),
            Text('IMPORT COMPLETE', style: AppType.titleL.copyWith(color: AppColors.primary)),
            const SizedBox(height: Space.s),
            Text('${r.sessions} sessions · ${r.sets} sets', style: AppType.title),
            if (r.customsCreated > 0)
              Text('${r.customsCreated} custom exercises created', style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
            if (r.achievements.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Text('Achievements unlocked: ${r.achievements.map((a) => a.title).join(', ')}', style: AppType.bodyS),
            ],
          ]),
        ),
        const SizedBox(height: Space.xl),
        BigButton(label: 'Done', onPressed: () => context.pop()),
      ];
}

class _MappingTile extends StatelessWidget {
  const _MappingTile(this.m, {required this.onTap});
  final NameMapping m;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (m.method) {
      MatchMethod.unmatched => AppColors.danger,
      MatchMethod.fuzzy when m.needsReview => AppColors.warning,
      _ => AppColors.textSecondary,
    };
    final conf = m.method == MatchMethod.fuzzy || m.method == MatchMethod.unmatched ? ' ${(m.confidence * 100).round()}%' : '';
    return ListTile(
      dense: true,
      title: Text(m.liftoffName, style: AppType.body),
      subtitle: Text(
        m.method == MatchMethod.unmatched ? 'No match: becomes a custom exercise. Tap to pick one.' : '→ ${m.exerciseName}',
        style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
      ),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${m.method.label}$conf'.toUpperCase(), style: AppType.label.copyWith(color: color, fontSize: 10)),
        Text('${m.sets} sets', style: AppType.bodyS.copyWith(color: AppColors.textTertiary, fontSize: 12)),
      ]),
      onTap: onTap,
    );
  }
}
