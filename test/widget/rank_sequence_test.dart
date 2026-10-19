import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/theme/app_theme.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';
import 'package:spotter/features/ranks/presentation/rank_sequence_screen.dart';
import 'package:spotter/features/workout/data/finish_service.dart';

RankChange gain(String name, RankChangeScope scope, RankScore? from, RankScore to) => RankChange(name: name, fromScore: from, toScore: to, scope: scope);

void main() {
  final gains = [
    gain('Bench', RankChangeScope.exercise, RankScore.of(Tier.silver, division: 3, rr: 80), RankScore.of(Tier.gold, division: 1, rr: 10)),
    gain('Squat', RankChangeScope.exercise, RankScore.of(Tier.gold, division: 2, rr: 10), RankScore.of(Tier.gold, division: 2, rr: 35)),
    gain('Chest', RankChangeScope.muscle, RankScore.of(Tier.gold, division: 1, rr: 10), RankScore.of(Tier.gold, division: 2, rr: 5)),
    gain('Arms', RankChangeScope.region, null, RankScore.of(Tier.bronze, division: 1, rr: 20)),
    gain('Overall', RankChangeScope.overall, RankScore.of(Tier.gold, division: 1, rr: 90), RankScore.of(Tier.gold, division: 2, rr: 10)),
  ];

  // Order as the Rank screen gives it: overall first, then the lifts.
  final ordered = [gains.last, gains[0], gains[1]];
  Widget app(VoidCallback onDone, {List<RankChange>? g}) => MaterialApp(theme: buildAppTheme(), home: RankSequenceScreen(gains: g ?? ordered, onDone: onDone));

  testWidgets('the ranks animate in the order given, one by one; nothing advances by itself, Continue appears at the end', (tester) async {
    var done = 0;
    await tester.pumpWidget(app(() => done++));
    await tester.pump();
    expect(find.byKey(const ValueKey('gain-overall-Overall')), findsOneWidget);
    expect(find.byKey(const ValueKey('gain-exercise-Bench')), findsNothing);
    expect(find.byKey(const ValueKey('after-continue')), findsNothing);

    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byKey(const ValueKey('gain-exercise-Bench')), findsOneWidget);
    expect(find.byKey(const ValueKey('gain-exercise-Squat')), findsOneWidget);
    expect(find.byKey(const ValueKey('after-continue')), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    expect(done, 0, reason: 'nothing auto-advances');
    expect(find.byKey(const ValueKey('after-continue')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('after-continue')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('after-continue')), warnIfMissed: false);
    expect(done, 1, reason: 'Continue calls it once');
  });

  testWidgets('a rank-up reads "from → to" when it lands; an RR-only gain shows +RR; a placement says NEW', (tester) async {
    await tester.pumpWidget(app(() {}, g: [gains[0], gains[1], gains[3]]));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.textContaining('Silver 3 → Gold 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('gain-lp-Bench')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.byKey(const ValueKey('gain-lp-Squat')), findsOneWidget);
    expect(find.text('+25 RR'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('NEW'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a tap fast-forwards the animation (Continue shows) but does not leave', (tester) async {
    var done = 0;
    await tester.pumpWidget(app(() => done++));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('after-continue')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('rank-sequence')));
    await tester.pump();
    expect(find.byKey(const ValueKey('after-continue')), findsOneWidget);
    expect(find.byKey(const ValueKey('gain-exercise-Squat')), findsOneWidget, reason: 'every row is shown');
    expect(done, 0);
  });

  testWidgets('nothing to show: says so and offers Continue at once', (tester) async {
    var done = 0;
    await tester.pumpWidget(app(() => done++, g: const []));
    await tester.pump();
    expect(find.text('No rank moved in this workout.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('after-continue')));
    expect(done, 1);
  });
}
