import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Library search finds the exercise from my Push routine under its routine name, the program name and sloppy spellings', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    await h.goTab(Icons.menu_book_outlined);
    await h.waitFor(find.byType(TextField), scroll: false);

    for (final q in ['high-to', 'high to low', 'hightolow', 'cable flye', 'HIGH-TO-LOW CABLE']) {
      debugPrint('STEP search "$q"');
      await tester.tap(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, q);
      await h.settle(8);
      await h.waitFor(find.byKey(const ValueKey('aka-Cable_Crossover')), scroll: false, reason: '"$q" finds Cable Crossover, shown as also known as');
      expect(find.text('Cable Crossover'), findsOneWidget);
    }
    await h.shot('library-search-alias');

    debugPrint('STEP the library name still works and shows no alias line');
    await tester.enterText(find.byType(TextField).first, 'cable cross');
    await h.settle(8);
    await h.waitFor(find.text('Cable Crossover'), scroll: false);
    expect(find.byKey(const ValueKey('aka-Cable_Crossover')), findsNothing);

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
