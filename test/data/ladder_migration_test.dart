import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/gamification/data/gamification_repository.dart';
import 'package:spotter/features/gamification/domain/achievements.dart';
import 'package:spotter/features/ranks/data/ladder_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 12);

  test('v3 silently revokes rank badges the new standards no longer support, keeps the rest, runs once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.putSetting(rankLadderVersionKey, '2');
    final repo = GamificationRepository(db);
    final defs = await GamificationRepository.loadAchievementDefs();
    // Unlocked by the old standards (a machine lift at Master) plus non-rank achievements.
    await repo.unlock(['rank_silver', 'rank_gold', 'rank_platinum', 'rank_diamond', 'rank_master', 'first_workout', 'first_pr'], DateTime(2026, 10, 1));

    // On the new standards the best lift is Platinum (index 4).
    const stats = AchievementStats(bestExerciseTierIndex: 4, sessions: 124);
    final r = await migrateRankLadder(db: db, stats: stats, defs: defs, now: now);
    expect(r.revoked.toSet(), {'rank_diamond', 'rank_master'});
    expect(r.unlocked, isEmpty);
    expect(await repo.unlockedKeys(), {'rank_silver', 'rank_gold', 'rank_platinum', 'first_workout', 'first_pr'});
    expect(await db.getSetting(rankLadderVersionKey), '$rankLadderVersion');

    // Second run is a no-op.
    const better = AchievementStats(bestExerciseTierIndex: 9);
    final again = await migrateRankLadder(db: db, stats: better, defs: defs, now: now);
    expect(again.unlocked, isEmpty);
    expect(again.revoked, isEmpty);
  });

  test('also unlocks rank badges the new standards qualify for', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final defs = await GamificationRepository.loadAchievementDefs();
    final r = await migrateRankLadder(db: db, stats: const AchievementStats(bestExerciseTierIndex: 3), defs: defs, now: now);
    expect(r.unlocked.toSet(), {'rank_silver', 'rank_gold'});
  });

  test('without a bodyweight nothing is revoked and the migration stays pending', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = GamificationRepository(db);
    await repo.unlock(['rank_master'], DateTime(2026, 10, 1));
    final defs = await GamificationRepository.loadAchievementDefs();
    final r = await migrateRankLadder(db: db, stats: const AchievementStats(bestExerciseTierIndex: -1), defs: defs, now: now, ranksKnown: false);
    expect(r.revoked, isEmpty);
    expect(await repo.unlockedKeys(), {'rank_master'});
    expect(await db.getSetting(rankLadderVersionKey), isNull);
  });
}
