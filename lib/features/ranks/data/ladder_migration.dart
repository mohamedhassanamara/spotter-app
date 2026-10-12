import '../../../core/db/database.dart';
import '../../gamification/data/gamification_repository.dart';
import '../../gamification/domain/achievements.dart';

/// Current rank ladder. v1: 7 tiers × 3 divisions. v2: League-style 10-tier ladder.
const int rankLadderVersion = 2;
const String rankLadderVersionKey = 'rank_ladder_version';

/// Moves an existing install onto the current ladder.
///
/// Ranks themselves are never stored: they're derived from logged sets every time they're shown, so
/// all history re-ranks on the new ladder automatically. The only persisted rank-dependent state is
/// achievements. Earned achievements are kept; ones that the new ladder now qualifies for (e.g. a lift
/// that is Platinum on the new ladder) are unlocked. Returns the keys unlocked by the migration.
Future<List<String>> migrateRankLadder({
  required AppDatabase db,
  required AchievementStats stats,
  required List<AchievementDef> defs,
  required DateTime now,
}) async {
  final current = int.tryParse(await db.getSetting(rankLadderVersionKey) ?? '') ?? 1;
  if (current >= rankLadderVersion) return const [];
  final repo = GamificationRepository(db);
  final unlocked = await repo.unlockedKeys();
  final fresh = const AchievementEvaluator()
      .newlyUnlocked(defs.where((d) => d.type == AchievementType.bestExerciseTier).toList(), stats, unlocked)
      .map((d) => d.key)
      .toList();
  if (fresh.isNotEmpty) await repo.unlock(fresh, now);
  await db.putSetting(rankLadderVersionKey, '$rankLadderVersion');
  return fresh;
}
