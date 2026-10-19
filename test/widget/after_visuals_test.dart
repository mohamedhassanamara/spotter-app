import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/theme/app_theme.dart';
import 'package:spotter/features/gamification/presentation/fire_streak.dart';
import 'package:spotter/features/workout/presentation/calculating_results.dart';

void main() {
  testWidgets('the loader says what it is doing and plays for at least 1.8 s', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const CalculatingResults()));
    expect(find.textContaining('Calculating your results'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, inExclusiveRange(0.3, 0.7), reason: 'the bar fills over the 1.8 s');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the flame ticks the streak up and reports when the show is over', (tester) async {
    var over = 0;
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: FireStreak(from: 4, to: 5, onDone: () => over++))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('4-day streak'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('5-day streak'), findsOneWidget);
    expect(over, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(over, 1);
  });

  testWidgets('Reduce Motion: the final state at once', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(data: const MediaQueryData(disableAnimations: true), child: Scaffold(body: FireStreak(from: 4, to: 5))),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('5-day streak'), findsOneWidget);
  });
}
