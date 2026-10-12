import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../library/domain/exercise_info.dart';
import '../../tutorials/data/edb_v2/edb_client.dart';
import '../../tutorials/data/edb_v2/edb_mapping_repository.dart';
import '../../tutorials/data/edb_v2/edb_providers.dart';
import '../../tutorials/domain/edb_v2_mapping.dart';

final edbMappingRepositoryProvider = Provider((ref) => EdbMappingRepository(ref.watch(databaseProvider)));

final _mapsProvider = StreamProvider<List<EdbV2Map>>((ref) => ref.watch(edbMappingRepositoryProvider).watchAll());

/// Fresh search results of this app session (images included). Never persisted: media URLs rotate
/// weekly and may not be stored on a plan without caching.
final _sessionHitsProvider = NotifierProvider<_SessionHits, Map<String, List<EdbSearchHit>>>(_SessionHits.new);

class _SessionHits extends Notifier<Map<String, List<EdbSearchHit>>> {
  @override
  Map<String, List<EdbSearchHit>> build() => const {};

  void put(String exerciseId, List<EdbSearchHit> hits) => state = {...state, exerciseId: hits};
}

/// Debug: the V2 review queue. Each queued exercise shows our image next to the candidates; one tap
/// confirms, "Search again" runs a typed query (1 API call). Export copies assets/edb_v2_map.json.
class EdbV2Review extends ConsumerWidget {
  const EdbV2Review({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maps = ref.watch(_mapsProvider).value ?? const <EdbV2Map>[];
    final catalog = ref.watch(catalogProvider).value ?? const <String, ExerciseInfo>{};
    final budget = ref.watch(edbBudgetProvider).value;
    final queued = maps.where((m) => m.status == 'queued').toList();
    final done = maps.where((m) => m.status == 'auto' || m.status == 'confirmed').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          '$done mapped · ${queued.length} to review · ${maps.where((m) => m.status == 'none').length} without a match'
          '${budget == null ? '' : ' · API ${budget.used}/2000 this month'}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('Copy edb_v2_map.json'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: await ref.read(edbMappingRepositoryProvider).exportJson()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Paste into assets/edb_v2_map.json')));
              }
            },
          ),
        ]),
        const SectionLabel('Review queue'),
        if (queued.isEmpty) const Text('Nothing to review.', style: TextStyle(color: AppColors.textSecondary)),
        for (final m in queued) _QueueCard(row: m, info: catalog[m.exerciseId]),
      ],
    );
  }
}

class _QueueCard extends ConsumerWidget {
  const _QueueCard({required this.row, required this.info});
  final EdbV2Map row;
  final ExerciseInfo? info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fresh = ref.watch(_sessionHitsProvider)[row.exerciseId];
    final stored = [
      for (final c in jsonDecode(row.candidates) as List<dynamic>)
        (id: (c as Map<String, dynamic>)['id'] as String, name: c['name'] as String, score: (c['score'] as num).toDouble(), image: null as String?),
    ];
    final candidates = fresh == null || info == null
        ? stored
        : [
            for (final c in scoreCandidates(info!, [for (final h in fresh) (id: h.exerciseId, name: h.name)]))
              (id: c.edbId, name: c.name, score: c.score, image: fresh.firstWhere((h) => h.exerciseId == c.edbId).imageUrl),
          ];
    final ours = info?.imageUrls.firstOrNull;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Thumb(url: ours),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(info?.name ?? row.exerciseId, style: AppType.title.copyWith(fontSize: 16)),
              Text('Searched "${row.query}" · best ${(row.confidence * 100).round()}%', style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        for (final c in candidates.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _Thumb(url: c.image),
            title: Text(c.name),
            subtitle: Text('${(c.score * 100).round()}% · tap to confirm'),
            onTap: () => ref.read(edbMappingRepositoryProvider).confirm(row.exerciseId, c.id, now: ref.read(clockProvider)()),
          ),
        Wrap(spacing: 8, children: [
          if (fresh == null)
            TextButton(onPressed: () => _search(context, ref, row.query), child: const Text('Show images (1 call)')),
          TextButton(
            onPressed: () async {
              final q = await promptText(context, title: 'Search ExerciseDB V2', initial: row.query);
              if (q != null && q.trim().isNotEmpty && context.mounted) await _search(context, ref, q.trim());
            },
            child: const Text('Search again'),
          ),
          TextButton(
            onPressed: () => ref.read(edbMappingRepositoryProvider).markNone(row.exerciseId, now: ref.read(clockProvider)()),
            child: const Text('No match'),
          ),
        ]),
      ]),
    );
  }

  Future<void> _search(BuildContext context, WidgetRef ref, String q) async {
    try {
      final hits = await ref.read(edbApiProvider).search(q);
      ref.read(_sessionHitsProvider.notifier).put(row.exerciseId, hits);
    } on EdbException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('V2 unavailable: ${e.code}')));
    }
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 56,
          height: 56,
          color: Colors.white,
          child: url == null
              ? const Icon(Icons.image_not_supported_outlined, color: Colors.black26)
              : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.black26)),
        ),
      );
}
