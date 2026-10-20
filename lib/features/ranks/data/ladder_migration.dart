import '../../../core/db/database.dart';
import '../../gamification/data/gamification_repository.dart';
import '../../gamification/domain/achievements.dart';

/// Current rank model. v1: 7 tiers × 3 divisions. v2: League-style 10-tier ladder.
/// v3: per-exercise standards (machines and cables stricter, apex tiers above "elite").
/// v4: allometric bodyweight scaling, accessories anchored to their base compound.
/// v5: only exercises in your routines (or done in an in-app workout) count toward ranks.
/// v6: Valorant ladder: 9 tiers (Iron … Immortal × 3 divisions, Radiant), RR instead of LP.
/// v7: the achievement rework (≈ 50 achievements, none rewarding following suggestions).
/// v8: Olympian joins above Champion (old Immortal's place) and Immortal becomes the top tier (old Radiant's): ranks are
/// derived so they shift by themselves; stored lift achievements are renamed (immortal → olympian, radiant → immortal).
const int rankLadderVersion = 8;
const String rankLadderVersionKey = 'rank_ladder_version';
const String _tierRenameKey = 'rank_tier_rename_v8';

class LadderMigration {
  const LadderMigration({this.unlocked = const [], this.revoked = const []});
  final List<String> unlocked;
  final List<String> revoked;
}

/// Moves an existing install onto the current rank model.
///
/// Ranks themselves are never stored: they're derived from logged sets every time they're shown, so
/// history re-ranks automatically. The only persisted rank-dependent state is achievements:
/// - rank achievements the new standards now qualify for are unlocked;
/// - from v3 (re-run for v4), rank achievements the *old* standards handed out and the new ones don't support are
///   revoked, silently (no notification, no rank-down animation). Achievements of every other
///   type were earned by real criteria and stay.
///
/// [ranksKnown] is false when ranks couldn't be computed (no bodyweight yet). Then nothing is revoked
/// and the migration stays pending, so a missing bodyweight never takes badges away.
Future<LadderMigration> migrateRankLadder({
  required AppDatabase db,
  required AchievementStats stats,
  required List<AchievementDef> defs,
  required DateTime now,
  bool ranksKnown = true,
}) async {
  final current = int.tryParse(await db.getSetting(rankLadderVersionKey) ?? '') ?? 1;
  if (current >= rankLadderVersion) return const LadderMigration();
  final repo = GamificationRepository(db);
  // Silent rename, once (the migration itself can stay pending without bodyweight): old Immortal is Olympian now, old
  // Radiant is Immortal. Order matters, and nothing is announced.
  if (current < 8 && await db.getSetting(_tierRenameKey) == null) {
    final old = await repo.watchUnlocked().first;
    await repo.revoke(['lift_immortal', 'lift_radiant']);
    if (old['lift_immortal'] != null) await repo.unlock(['lift_olympian'], old['lift_immortal']!);
    if (old['lift_radiant'] != null) await repo.unlock(['lift_immortal'], old['lift_radiant']!);
    await db.putSetting(_tierRenameKey, '1');
  }
  if (!ranksKnown) return const LadderMigration();
  final have = await repo.unlockedKeys();
  const eval = AchievementEvaluator();
  final known = {for (final d in defs) d.key};
  // Silently: achievements this version no longer has (e.g. Patience, Disciplined, Comeback) go, earned ones that the
  // new definitions also qualify for unlock, and rank-based ones the new ladder doesn't support are revoked.
  final retired = [for (final k in have) if (!known.contains(k)) k];
  final fresh = eval.newlyUnlocked(defs, stats, have).map((d) => d.key).toList();
  final revoked = [
    for (final d in defs)
      if (d.isRankBased && have.contains(d.key) && !eval.isMet(d, stats)) d.key,
  ];
  if (fresh.isNotEmpty) await repo.unlock(fresh, now);
  if (retired.isNotEmpty || revoked.isNotEmpty) await repo.revoke([...retired, ...revoked]);
  await db.putSetting(rankLadderVersionKey, '$rankLadderVersion');
  return LadderMigration(unlocked: fresh, revoked: [...retired, ...revoked]);
}
