import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/motion.dart';
import 'package:spotter/core/widgets/game_ui.dart';

Widget _app(Widget child, {bool reduce = false}) =>
    MaterialApp(home: Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduce), child: Scaffold(body: child))));

void main() {
  testWidgets('count-up animates normally and jumps to the value under Reduce Motion', (tester) async {
    await tester.pumpWidget(_app(const CountUp(value: 100, suffix: ' XP')));
    await tester.pump(const Duration(milliseconds: 200));
    final mid = int.parse(tester.widget<Text>(find.byType(Text)).data!.split(' ').first);
    expect(mid, inInclusiveRange(1, 99), reason: 'still counting');
    await tester.pumpAndSettle();
    expect(find.text('100 XP'), findsOneWidget);

    await tester.pumpWidget(_app(const CountUp(value: 100, suffix: ' XP'), reduce: true));
    await tester.pump();
    expect(find.text('100 XP'), findsOneWidget, reason: 'no counting with Reduce Motion');
  });

  testWidgets('list items fade in one after the other; with Reduce Motion they are simply there', (tester) async {
    Widget list(bool reduce) => _app(Column(children: [for (var i = 0; i < 3; i++) FadeSlideIn(index: i, child: Text('row $i'))]), reduce: reduce);
    await tester.pumpWidget(list(false));
    double opacity(int i) => tester.widget<Opacity>(find.ancestor(of: find.text('row $i'), matching: find.byType(Opacity)).first).opacity;
    await tester.pump(const Duration(milliseconds: 120));
    expect(opacity(0), greaterThan(opacity(2)), reason: 'staggered: the first row is ahead of the last');
    await tester.pumpAndSettle();
    expect(opacity(2), 1);

    await tester.pumpWidget(list(true));
    expect(find.ancestor(of: find.text('row 1'), matching: find.byType(Opacity)), findsNothing, reason: 'no entrance animation');
  });

  testWidgets('tab switch: the new tab fades in, every tab keeps its state, only one is shown', (tester) async {
    Widget tabs(int i) => _app(FadeBranches(currentIndex: i, children: [const _Counter(key: ValueKey('a')), const _Counter(key: ValueKey('b'))]));
    await tester.pumpWidget(tabs(0));
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(tabs(1));
    await tester.pump(const Duration(milliseconds: 60));
    final fading = tester.widget<FadeTransition>(find.ancestor(of: find.byKey(const ValueKey('b')), matching: find.byType(FadeTransition)).first);
    expect(fading.opacity.value, inExclusiveRange(0, 1));
    expect(find.text('1'), findsNothing, reason: 'tab a is hidden meanwhile');
    await tester.pumpAndSettle();

    await tester.pumpWidget(tabs(0));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget, reason: 'tab a kept its counter');
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: () => setState(() => n++), child: Center(child: Text('$n')));
}
