import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const supersetColors = [AppColors.accent, AppColors.xp, AppColors.warning, Color(0xFFFF7A45)];

/// "A1", "A2", "B1"… and the group's bar color, keyed by item id. Groups of one aren't supersets.
Map<int, ({String label, Color color})> supersetLabels<T>(List<T> items, {required int Function(T) id, required int? Function(T) group}) {
  final groups = <int, List<T>>{};
  for (final e in items) {
    final g = group(e);
    if (g != null) (groups[g] ??= []).add(e);
  }
  groups.removeWhere((_, v) => v.length < 2);
  final order = groups.keys.toList();
  return {
    for (final (gi, g) in order.indexed)
      for (final (i, e) in groups[g]!.indexed)
        id(e): (label: '${String.fromCharCode(65 + gi)}${i + 1}', color: supersetColors[gi % supersetColors.length]),
  };
}
