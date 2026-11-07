import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/app_providers.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/theme/app_theme.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';
import 'package:spotter/features/ranks/domain/exercise_rank_state.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';
import 'package:spotter/features/ranks/presentation/rank_row.dart';

/// The rank row is two fixed-height lines: the text never wraps and the card does not change height when the mode or the text changes.
void main() {
  final standards = RanksRepository.parseStandards(File('assets/strength_standards.json').readAsStringSync());
  final bench = standards.firstWhere((s) => s.id == 'bench_press');
  final grid = WeightGrid([for (var w = 20.0; w <= 300; w += 2.5) w]);

  ExerciseRankState state({RankScore? score, double bw = 80, bool hidden = false}) =>
      ExerciseRankState(exerciseId: 'x', hidden: hidden, standard: bench, baseline: null, score: score, bodyweight: bw);

  Future<Size> pump(WidgetTester tester, {required double width, required double scale, required RankTargetMode mode, required ExerciseRankState st}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        exerciseRankStateProvider.overrideWith((ref, id) => st),
        exerciseGridProvider.overrideWith((ref, id) => grid),
        rankTargetModeProvider.overrideWith(() => _Mode(mode)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                key: const ValueKey('card'),
                child: const RankRow(exerciseId: 'x', repMin: 6, rir: 2),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    return tester.getSize(find.byKey(const ValueKey('card')));
  }

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.5, 2.5]) {
      testWidgets('width $width, text ×$scale: one text line, same height in Lift and BW, ranked/unranked/no-bodyweight', (tester) async {
        final heights = <double>[];
        for (final st in [
          state(score: RankScore.of(Tier.platinum, division: 3, rr: 80)),
          state(score: null),
          state(score: RankScore.of(Tier.gold, division: 2), bw: 0),
        ]) {
          for (final mode in RankTargetMode.values) {
            final size = await pump(tester, width: width, scale: scale, mode: mode, st: st);
            heights.add(size.height);
            expect(tester.takeException(), isNull, reason: 'no overflow');
            final line = tester.getSize(find.byKey(const ValueKey('rank-gap-x')));
            final oneLine = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('rank-gap-x')), matching: find.byType(Text)));
            expect(oneLine.maxLines, 1);
            expect(line.height, lessThan(30 * 1.3 * 1.3 * 1.5), reason: 'a single line tall');
            // The control keeps its width and sits at the right edge of the card.
            final toggle = tester.getRect(find.byKey(const ValueKey('rank-mode-toggle')));
            expect(toggle.width, rankModeToggleWidth);
            expect(toggle.right, closeTo(width - 16, 0.6));
          }
        }
        expect(heights.toSet().length, 1, reason: 'card height identical across modes and states: $heights');
      });
    }
  }

  testWidgets('tapping line 2 opens the detail sheet with the full text, the estimate flag and the bodyweight sentence', (tester) async {
    final est = ExerciseRankState(
        exerciseId: 'x',
        hidden: false,
        standard: StrengthStandard(id: 'e', name: 'E', kind: StandardKind.free, exerciseIds: const ['x'], anchors: const [0.6, 0.85, 1.15, 1.5, 1.9], estimated: true),
        baseline: null,
        score: RankScore.of(Tier.gold, division: 1),
        bodyweight: 80);
    await pump(tester, width: 320, scale: 1, mode: RankTargetMode.bodyweight, st: est);
    await tester.tap(find.byKey(const ValueKey('rank-row-line2-x')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rank-detail-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('rank-detail-estimated')), findsOneWidget);
    expect(find.textContaining('gaining bodyweight without lifting more can lower it'), findsOneWidget);
    expect(find.textContaining('x BW'), findsWidgets);
  });
}

class _Mode extends RankTargetModeNotifier {
  _Mode(this._m);
  final RankTargetMode _m;
  @override
  RankTargetMode build() => _m;
}
