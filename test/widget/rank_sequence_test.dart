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

  Widget app(VoidCallback onDone) => MaterialApp(theme: buildAppTheme(), home: RankSequenceScreen(gains: gains, onDone: onDone));

  testWidgets('every lift, then muscles and regions, then the overall rank, in turn; ends by itself', (tester) async {
    var done = 0;
    await tester.pumpWidget(app(() => done++));
    await tester.pump();
    // Only the first lift has started.
    expect(find.byKey(const ValueKey('gain-exercise-Bench')), findsOneWidget);
    expect(find.byKey(const ValueKey('gain-exercise-Squat')), findsNothing);
    expect(find.text('Overall'), findsNothing);

    // Each row takes budget / 5 = 1 s (capped), so after 2.5 s: both lifts, the muscle has started.
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byKey(const ValueKey('gain-exercise-Squat')), findsOneWidget);
    expect(find.byKey(const ValueKey('gain-muscle-Chest')), findsOneWidget);
    expect(find.byKey(const ValueKey('gain-overall-Overall')), findsNothing, reason: 'overall comes last');

    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byKey(const ValueKey('gain-region-Arms')), findsOneWidget);
    expect(find.byKey(const ValueKey('gain-overall-Overall')), findsOneWidget);
    expect(done, 0);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(done, 1, reason: 'ends by itself, once');
  });

  testWidgets('a rank-up reads "from → to" when it lands; an RR-only gain shows +RR; a placement says NEW', (tester) async {
    await tester.pumpWidget(app(() {}));
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

  testWidgets('a tap skips the whole sequence, once', (tester) async {
    var done = 0;
    await tester.pumpWidget(app(() => done++));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('rank-sequence')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rank-sequence')));
    await tester.pump();
    expect(done, 1);
    await tester.pump(const Duration(seconds: 10)); // the timeline finishing later must not call it again
    expect(done, 1);
  });

  testWidgets('nothing to show: finishes at once', (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: RankSequenceScreen(gains: const [], onDone: () => done++)));
    await tester.pump();
    expect(done, 1);
  });
}
