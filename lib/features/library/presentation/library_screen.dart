import 'package:flutter/material.dart';

import '../../../core/motion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../domain/exercise_filter.dart';
import '../domain/exercise_info.dart';
import 'exercise_thumb.dart';
import '../domain/muscle_mapping.dart';

/// Exercise catalogue: search, filter, favorites. In [pickMode] tapping an exercise returns its id.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.pickMode = false});

  final bool pickMode;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  ExerciseFilter _filter = const ExerciseFilter();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickMuscle() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _OptionSheet(
        title: 'Muscle',
        options: [for (final m in datasetMuscles) (m, _cap(m))],
        selected: _filter.muscle,
      ),
    );
    if (picked == null) return;
    setState(() => _filter = _filter.copyWith(muscle: () => picked.isEmpty ? null : picked));
  }

  Future<void> _pickEquipment(Map<String, ExerciseInfo> catalog) async {
    final values = <String>{for (final e in catalog.values) e.equipment ?? ExerciseFilter.noEquipment}.toList()..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _OptionSheet(
        title: 'Equipment',
        options: [for (final v in values) (v, v == ExerciseFilter.noEquipment ? 'None listed' : _cap(v))],
        selected: _filter.equipment,
      ),
    );
    if (picked == null) return;
    setState(() => _filter = _filter.copyWith(equipment: () => picked.isEmpty ? null : picked));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.pickMode ? 'Add exercise' : 'Library')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: widget.pickMode ? 'pick-custom' : 'library-custom',
        onPressed: () => context.push(Routes.newExercise),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Custom'),
      ),
      body: AsyncBody<Map<String, ExerciseInfo>>(
        value: catalog,
        builder: (all) {
          final results = _filter.apply(all.values);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search ${all.length} exercises',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              setState(() => _filter = _filter.copyWith(query: ''));
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _filter = _filter.copyWith(query: v.trim())),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    FilterChip(
                      label: const Text('Favorites'),
                      avatar: const Icon(Icons.star_rounded, size: 18),
                      selected: _filter.favoritesOnly,
                      onSelected: (v) => setState(() => _filter = _filter.copyWith(favoritesOnly: v)),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(_filter.muscle == null ? 'Muscle' : _cap(_filter.muscle!)),
                      selected: _filter.muscle != null,
                      onSelected: (_) => _pickMuscle(),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(_filter.equipment == null
                          ? 'Equipment'
                          : _filter.equipment == ExerciseFilter.noEquipment
                              ? 'No equipment'
                              : _cap(_filter.equipment!)),
                      selected: _filter.equipment != null,
                      onSelected: (_) => _pickEquipment(all),
                    ),
                    if (_filter.isActive) ...[
                      const SizedBox(width: 8),
                      ActionChip(
                        label: const Text('Clear'),
                        avatar: const Icon(Icons.filter_alt_off_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _filter = const ExerciseFilter());
                        },
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${results.length} ${results.length == 1 ? 'exercise' : 'exercises'}',
                    style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: results.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matches',
                        message: 'Try another search or clear the filters. You can also create a custom exercise.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: results.length,
                        itemBuilder: (context, i) => FadeSlideIn(
                          index: i,
                          child: ExerciseListTile(
                          heroTag: widget.pickMode ? null : 'ex-hero-${results[i].id}',
                          exercise: results[i],
                          onTap: () => widget.pickMode
                              ? context.pop(results[i].id)
                              : context.push(Routes.exercise(results[i].id)),
                          onFavorite: () => ref
                              .read(exerciseRepositoryProvider)
                              .setFavorite(results[i].id, !results[i].isFavorite),
                        )),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One exercise row with thumbnail and favorite toggle.
class ExerciseListTile extends StatelessWidget {
  const ExerciseListTile({super.key, required this.exercise, required this.onTap, this.onFavorite, this.trailing, this.heroTag});

  final ExerciseInfo exercise;
  final String? heroTag;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            heroTag == null ? ExerciseThumb(exercise: e, size: 56) : Hero(tag: heroTag!, child: ExerciseThumb(exercise: e, size: 56)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    [_cap(e.muscleSummary), if (e.equipment != null) _cap(e.equipment!), if (e.isCustom) 'Custom'].join(' · '),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ?trailing,
            if (onFavorite != null)
              IconButton(
                iconSize: 26,
                tooltip: e.isFavorite ? 'Remove favorite' : 'Add favorite',
                onPressed: onFavorite,
                icon: Icon(e.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                    color: e.isFavorite ? AppColors.warning : AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionSheet extends StatelessWidget {
  const _OptionSheet({required this.title, required this.options, required this.selected});
  final String title;
  final List<(String, String)> options;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
                if (selected != null) TextButton(onPressed: () => Navigator.of(context).pop(''), child: const Text('Any')),
              ]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (value, label) in options)
                    ListTile(
                      minTileHeight: 52,
                      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: value == selected ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                      onTap: () => Navigator.of(context).pop(value),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
