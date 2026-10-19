import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/theme/app_theme.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';
import 'package:spotter/features/ranks/presentation/rank_badge.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Valorant ladder: nine tiers with their colors and badges, three divisions, Radiant without divisions', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    debugPrint('STEP Settings → Debug menu → Rank badges');
    await h.goTab(Icons.person_outline_rounded);
    await h.tap(find.byTooltip('Settings'));
    await h.tap(find.text('Debug menu'));
    await h.waitFor(find.text('Rank badges & rank-up preview'));
    await h.tap(find.text('Rank badges & rank-up preview'));
    await h.waitFor(find.text('Radiant'), scroll: false);
    for (final t in Tier.values) {
      expect(find.text(t.label), findsWidgets, reason: '${t.label} in the gallery');
    }
    for (final gone in ['Emerald', 'Master', 'Grandmaster', 'Challenger']) {
      expect(find.text(gone), findsNothing, reason: '$gone is not a Valorant tier');
    }
    expect(find.byType(RankBadge), findsWidgets);
    final label = tester.widget<Text>(find.text('Gold').first);
    expect(label.style?.color, tierColors[Tier.gold.index], reason: 'Gold uses Valorant gold');
    await h.shot('valorant-badges');

    debugPrint('STEP divisions 1, 2, 3 of one tier');
    await tester.drag(find.byType(ListView).first, const Offset(0, -500), warnIfMissed: false);
    await h.settle(4);
    await h.shot('valorant-divisions');
    for (var d = 1; d <= 3; d++) {
      expect(RankScore.of(Tier.gold, division: d).label, 'Gold $d');
    }
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
