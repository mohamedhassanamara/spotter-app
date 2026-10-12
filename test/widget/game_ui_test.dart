import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/widgets/game_ui.dart';

void main() {
  testWidgets('CountUp ends exactly on its value', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CountUp(value: 245, prefix: '+', suffix: ' XP')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('+245 XP'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('+245 XP'), findsOneWidget);
  });

  testWidgets('StepperBox taps once and repeats on long-press', (tester) async {
    var v = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (_, set) => StepperBox(value: '$v', onMinus: () => set(() => v--), onPlus: () => set(() => v++)),
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(v, 1);
    final g = await tester.startGesture(tester.getCenter(find.byIcon(Icons.add_rounded)));
    await tester.pump(const Duration(milliseconds: 600)); // long-press recognised
    await tester.pump(const Duration(milliseconds: 500)); // ~4 repeats
    await g.up();
    expect(v, greaterThan(4));
  });

  testWidgets('DayDots renders a week', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DayDots(states: [
          DayDotState.trained,
          DayDotState.trained,
          DayDotState.smartRest,
          DayDotState.today,
          DayDotState.future,
          DayDotState.future,
          DayDotState.future,
        ]),
      ),
    ));
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.bedtime_rounded), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
  });
}
