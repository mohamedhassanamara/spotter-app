import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../data/rank_exclusions.dart';

/// "Counts toward rank" for one exercise. The muscle sheet, the Ranks tab and the exercise page all
/// read and write the same setting, so they stay in sync and ranks recompute at once.
class RankToggle extends ConsumerWidget {
  const RankToggle({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(rankExclusionsProvider).value ?? const <String>{};
    return Tooltip(
      message: 'Counts toward rank',
      child: Switch(
        key: ValueKey('rank-toggle-$exerciseId'),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        value: !hidden.contains(exerciseId),
        onChanged: (on) => RankExclusions(ref.read(databaseProvider)).set(exerciseId, excluded: !on),
      ),
    );
  }
}
