import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/muscle_mapping.dart';

/// Equipment choices for custom exercises (dataset values; null = none).
const List<String?> customEquipmentOptions = [
  'barbell',
  'dumbbell',
  'cable',
  'machine',
  'kettlebells',
  'body only',
  'bands',
  'e-z curl bar',
  'other',
  null,
];

/// Create or edit a custom exercise.
class CustomExerciseScreen extends ConsumerStatefulWidget {
  const CustomExerciseScreen({super.key, this.editId});

  final String? editId;

  @override
  ConsumerState<CustomExerciseScreen> createState() => _CustomExerciseScreenState();
}

class _CustomExerciseScreenState extends ConsumerState<CustomExerciseScreen> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  final _primary = <String>{};
  final _secondary = <String>{};
  String? _equipment = 'barbell';
  bool _compound = true;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.editId == null) {
      _loaded = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final info = await ref.read(exerciseRepositoryProvider).byId(widget.editId!);
    if (!mounted) return;
    setState(() {
      if (info != null) {
        _name.text = info.name;
        _notes.text = info.notes ?? '';
        _primary.addAll(info.primaryMuscles);
        _secondary.addAll(info.secondaryMuscles);
        _equipment = info.equipment;
        _compound = info.isCompound;
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && _primary.isNotEmpty;

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final repo = ref.read(exerciseRepositoryProvider);
    final secondary = _secondary.difference(_primary).toList();
    if (widget.editId == null) {
      await repo.createCustom(
        name: _name.text,
        primaryMuscles: _primary.toList(),
        secondaryMuscles: secondary,
        equipment: _equipment,
        compound: _compound,
        notes: _notes.text,
      );
    } else {
      await repo.updateCustom(
        widget.editId!,
        name: _name.text,
        primaryMuscles: _primary.toList(),
        secondaryMuscles: secondary,
        equipment: _equipment,
        compound: _compound,
        notes: _notes.text,
      );
    }
    if (mounted) context.pop();
  }

  Widget _muscleChips(Set<String> selected, Set<String> disabled) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in datasetMuscles)
            FilterChip(
              label: Text(m[0].toUpperCase() + m.substring(1)),
              selected: selected.contains(m),
              onSelected: disabled.contains(m)
                  ? null
                  : (v) => setState(() => v ? selected.add(m) : selected.remove(m)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.editId != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit exercise' : 'Custom exercise')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SectionHeader('Primary muscles'),
                _muscleChips(_primary, const {}),
                if (_primary.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Pick at least one.', style: TextStyle(color: AppColors.warning)),
                  ),
                const SectionHeader('Secondary muscles'),
                _muscleChips(_secondary, _primary),
                const SectionHeader('Equipment'),
                DropdownButtonFormField<String?>(
                  initialValue: _equipment,
                  items: [
                    for (final e in customEquipmentOptions)
                      DropdownMenuItem(value: e, child: Text(e == null ? 'None' : e[0].toUpperCase() + e.substring(1))),
                  ],
                  onChanged: (v) => setState(() => _equipment = v),
                ),
                const SectionHeader('Type'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Compound'), icon: Icon(Icons.account_tree_rounded)),
                    ButtonSegment(value: false, label: Text('Isolation'), icon: Icon(Icons.adjust_rounded)),
                  ],
                  selected: {_compound},
                  onSelectionChanged: (s) => setState(() => _compound = s.first),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Compounds default to 6–10 reps, isolations to 10–15.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
                const SectionHeader('Notes (optional)'),
                TextField(
                  controller: _notes,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Setup, cues, machine settings…'),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _valid && !_saving ? _save : null,
            child: Text(editing ? 'Save changes' : 'Create exercise'),
          ),
        ),
      ),
    );
  }
}
