import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../ranks/domain/ranks.dart';
import '../../ranks/presentation/rank_badge.dart';
import '../../ranks/presentation/rank_up_screen.dart';

/// Debug-only: every tier and size, plus a rank-up preview.
class BadgeGalleryScreen extends StatelessWidget {
  const BadgeGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rank badges'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (ctx) => RankUpScreen(changes: demoRankUps(), onDone: () => Navigator.of(ctx).pop()),
            )),
            child: const Text('Rank-up'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            childAspectRatio: 0.78,
            children: [
              for (final t in Tier.values)
                Column(children: [
                  RankBadge(score: RankScore.of(t, division: 2), size: BadgeSize.medium, width: 92),
                  const SizedBox(height: 6),
                  Text(t.label, style: TextStyle(color: tierColors[t.index], fontWeight: FontWeight.w800)),
                ]),
              const Column(children: [
                RankBadge(score: null, width: 92),
                SizedBox(height: 6),
                Text('Unranked', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800)),
              ]),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Divisions', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [for (var d = 1; d <= 3; d++) RankBadge(score: RankScore.of(Tier.gold, division: d), width: 64)],
          ),
          const SizedBox(height: 24),
          const Text('Sizes', style: TextStyle(color: AppColors.textSecondary)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final s in BadgeSize.values) RankBadge(score: RankScore.of(Tier.radiant, rr: 340), size: s),
            ],
          ),
        ],
      ),
    );
  }
}
