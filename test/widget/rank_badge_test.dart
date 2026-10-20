import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';
import 'package:spotter/features/ranks/presentation/rank_badge.dart';
import 'package:spotter/features/ranks/presentation/rank_up_screen.dart';
import 'package:spotter/features/workout/data/finish_service.dart';

void main() {
  testWidgets('every tier and size paints', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Wrap(children: [
            for (final t in Tier.values)
              for (final s in BadgeSize.values) RankBadge(score: RankScore.of(t, division: 3), size: s),
            const RankBadge(score: null),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(RankBadge), findsNWidgets(Tier.values.length * BadgeSize.values.length + 1));
  });

  testWidgets('Immortal animates, divisional badges are static', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RankBadge(score: RankScore.of(Tier.immortal))));
    expect(find.byType(AnimatedBuilder), findsWidgets);
    await tester.pumpWidget(MaterialApp(home: RankBadge(score: RankScore.of(Tier.gold, division: 2))));
    expect(
      find.descendant(of: find.byType(RankBadge), matching: find.byType(AnimatedBuilder)),
      findsNothing,
    );
  });

  test('rank-up vs first placement vs rank-down', () {
    final up = RankChange(name: 'a', fromScore: RankScore(10), toScore: RankScore(11.2), scope: RankChangeScope.muscle);
    final placed = RankChange(name: 'b', fromScore: null, toScore: RankScore(4), scope: RankChangeScope.exercise);
    final down = RankChange(name: 'c', fromScore: RankScore(9), toScore: RankScore(7.5), scope: RankChangeScope.muscle);
    expect([up.isRankUp, placed.isRankUp, down.isRankUp], [true, false, false]);
    expect([up.up, placed.up, down.up], [true, true, false]);
  });

  testWidgets('rank-up screen finishes once: on tap or after 2.6 s', (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(home: RankUpScreen(changes: demoRankUps(), onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('PLATINUM 1'), findsOneWidget, reason: 'overall is the hero');
    await tester.tap(find.byType(RankUpScreen));
    expect(done, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(done, 1, reason: 'no second callback when the animation ends');

    var done2 = 0;
    await tester.pumpWidget(MaterialApp(home: RankUpScreen(key: UniqueKey(), changes: demoRankUps(), onDone: () => done2++)));
    await tester.pump(RankUpScreen.duration + const Duration(milliseconds: 50));
    expect(done2, 1);
    expect(RankUpScreen.duration, lessThan(const Duration(seconds: 3)));
  });
}
