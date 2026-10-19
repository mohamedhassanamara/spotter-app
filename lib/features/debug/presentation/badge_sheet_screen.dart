import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../ranks/domain/ranks.dart';
import '../../ranks/presentation/rank_badge.dart';

/// Debug-only: every tier with its three divisions side by side (Radiant has none), for checking that a tier stays recognizable while its divisions
/// visibly climb.
class BadgeSheetScreen extends StatelessWidget {
  const BadgeSheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Badge sheet')),
      body: ListView(
        key: const ValueKey('badge-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          for (final t in Tier.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 92, child: Text(t.label, style: TextStyle(color: tierColors[t.index], fontWeight: FontWeight.w800, fontSize: 15))),
                if (t == Tier.radiant)
                  RankBadge(score: RankScore.of(Tier.radiant, rr: 120), width: 64, animate: false)
                else
                  for (var d = 1; d <= 3; d++) ...[
                    Expanded(child: Center(child: RankBadge(key: ValueKey('sheet-${t.name}-$d'), score: RankScore.of(t, division: d, rr: 50), width: 64, animate: false))),
                  ],
                if (t == Tier.radiant) const Expanded(child: SizedBox()),
              ]),
            ),
        ],
      ),
    );
  }
}
