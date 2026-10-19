import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Badge sheet (Settings → Debug menu): every tier with its three divisions side by side', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await h.goTab(Icons.person_outline_rounded);
    await h.tap(find.byTooltip('Settings'));
    await h.tap(find.text('Debug menu'));
    await h.waitFor(find.byKey(const ValueKey('badge-sheet-tile')));
    await h.tap(find.byKey(const ValueKey('badge-sheet-tile')));
    await h.waitFor(find.byKey(const ValueKey('badge-sheet')), scroll: false);
    await h.settle(10);
    for (final t in Tier.values.where((t) => !t.isApex)) {
      for (var d = 1; d <= 3; d++) {
        expect(find.byKey(ValueKey('sheet-${t.name}-$d')), findsOneWidget, reason: '${t.label} division $d');
      }
    }
    expect(find.text('Radiant'), findsOneWidget);
    await h.shot('badge-sheet');
    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
