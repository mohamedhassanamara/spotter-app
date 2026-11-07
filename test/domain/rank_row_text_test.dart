import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';
import 'package:spotter/features/ranks/domain/rank_row_text.dart';
import 'package:spotter/features/ranks/domain/rank_target.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

void main() {
  final standards = RanksRepository.parseStandards(File('assets/strength_standards.json').readAsStringSync());
  final bench = standards.firstWhere((s) => s.id == 'bench_press');
  final assisted = standards.firstWhere((s) => s.id == 'assisted_pull_up');
  final gold1 = RankScore.of(Tier.gold, division: 1, rr: 40);
  const set = RankTargetSet(reps: 6, weight: 72.5, atMax: false);

  RankRowText text({required bool bw, double weight = 80, RankScore? score, RankTargetSet? s = set, StrengthStandard? std, bool hidden = false, String? next = 'Gold 2'}) =>
      buildRankRowText(hidden: hidden, bodyweightMode: bw, bodyweight: weight, score: score ?? gold1, standard: std ?? bench, nextLabel: next, set: s);

  test('lift mode: "6 × 72.5 kg → Gold 2"', () {
    expect(text(bw: false).line, '6 × 72.5 kg → Gold 2');
  });

  test('bodyweight mode: current relative strength and the next target in x BW with the kg at today\'s bodyweight', () {
    final t = text(bw: true).line;
    final now = relativeStrength(score: gold1, standard: bench, bodyweight: 80)!;
    expect(t, '${now.toStringAsFixed(2)}x BW → Gold 2: 6 × 0.91x BW (about 72.5 kg at 80 kg)');
    expect(t, isNot(contains('What if')));
    expect(t, isNot(contains('lower this rank')));
    expect(t.contains('\n'), isFalse);
  });

  test('relative strength is e1RM ÷ bodyweight and round-trips with the score', () {
    // A 100 kg × 5 set at RPE 10 on bench at 80 kg: e1RM = 100 × (1 + 5/30).
    final e1rm = scoringE1rm(load: 100, reps: 5, rpe: 10);
    final score = bench.scoreForRatio(bench.ratioFor(e1rm, 80));
    expect(relativeStrength(score: score, standard: bench, bodyweight: 80)!, closeTo(e1rm / 80, 1e-6));
  });

  test('bodyweight lifts count the bodyweight in the load (assisted: assistance is negative)', () {
    const pull = RankTargetSet(reps: 8, weight: -20, atMax: false);
    final t = buildRankRowText(
        hidden: false, bodyweightMode: true, bodyweight: 80, score: gold1, standard: assisted, nextLabel: 'Gold 2', set: pull);
    expect(t.line, contains('8 × 0.75x BW (about 60 kg at 80 kg)'));
  });

  test('unranked: the target is Bronze 1 and there is no current ratio', () {
    final lift = buildRankRowText(hidden: false, bodyweightMode: false, bodyweight: 80, score: null, standard: bench, nextLabel: 'Bronze 1', set: set);
    expect(lift.line, '6 × 72.5 kg → Bronze 1');
    final bw = buildRankRowText(hidden: false, bodyweightMode: true, bodyweight: 80, score: null, standard: bench, nextLabel: 'Bronze 1', set: set);
    expect(bw.line, startsWith('→ Bronze 1: 6 × '));
  });

  test('no bodyweight: "Set your bodyweight" in both modes (tap opens the input)', () {
    for (final mode in [false, true]) {
      final t = text(bw: mode, weight: 0);
      expect(t.line, 'Set your bodyweight');
      expect(t.needsBodyweight, isTrue);
    }
  });

  test('hidden, top of the ladder and unreachable', () {
    expect(text(bw: false, hidden: true).line, 'Hidden from ranks');
    final top = buildRankRowText(hidden: false, bodyweightMode: true, bodyweight: 80, score: RankScore.of(Tier.immortal), standard: bench, nextLabel: null, set: null);
    expect(top.isTop, isTrue);
    expect(text(bw: true, s: null).line, rankTargetUnreachable);
  });
}
