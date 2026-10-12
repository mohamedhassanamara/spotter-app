import 'dart:math' as math;

import '../../../core/domain/training.dart';

/// XP rules.
class XpRules {
  const XpRules();

  static const int perWorkingSet = 10;
  static const int followBonus = 15;
  static const int perPr = 50;
  static const int weeklyGoal = 100;
  static const int perQuest = 40;

  /// 0 XP for override sets; otherwise +10, +15 more when the suggestion was followed (±5 %).
  int forSet(LoggedSet s) {
    if (!s.isWorking || s.isOverride) return 0;
    return perWorkingSet + (s.followedSuggestion ? followBonus : 0);
  }

  int forSession({required Iterable<LoggedSet> sets, required int prCount}) =>
      sets.fold<int>(0, (sum, s) => sum + forSet(s)) + prCount * perPr;
}

class LevelInfo {
  const LevelInfo({required this.level, required this.xpIntoLevel, required this.xpForNext, required this.totalXp});
  final int level;
  final int xpIntoLevel;
  final int xpForNext;
  final int totalXp;

  double get progress => xpForNext == 0 ? 0 : xpIntoLevel / xpForNext;
}

/// XP needed to go from [level] to level + 1: `100 × level^1.5`.
int xpToAdvance(int level) => (100 * math.pow(level, 1.5)).round();

LevelInfo levelFor(int totalXp) {
  var level = 1;
  var remaining = math.max(0, totalXp);
  while (remaining >= xpToAdvance(level)) {
    remaining -= xpToAdvance(level);
    level++;
  }
  return LevelInfo(level: level, xpIntoLevel: remaining, xpForNext: xpToAdvance(level), totalXp: totalXp);
}

/// PR detection: a session's best valid e1RM beats the previous all-time best valid e1RM.
/// The first ever session of an exercise is not a PR (it sets the baseline).
bool isPr({required double previousBest, required double sessionBest}) =>
    previousBest > 0 && sessionBest > previousBest + 0.05;
