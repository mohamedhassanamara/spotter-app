import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/gamification/data/gamification_repository.dart';
import 'package:spotter/features/gamification/domain/achievements.dart';
import 'package:spotter/features/ranks/data/ladder_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v1 → v2 keeps earned achievements, unlocks newly qualifying rank ones, runs once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = GamificationRepository(db);
    final defs = await GamificationRepository.loadAchievementDefs();
    final now = DateTime(2026, 10, 12);
    await repo.unlock(['rank_silver', 'first_workout'], DateTime(2026, 9, 1));

    // A lift that is Platinum (index 4) on the new ladder.
    const stats = AchievementStats(bestExerciseTierIndex: 4, sessions: 3);
    final fresh = await migrateRankLadder(db: db, stats: stats, defs: defs, now: now);
    expect(fresh.toSet(), {'rank_gold', 'rank_platinum'});
    expect(await repo.unlockedKeys(), containsAll(['rank_silver', 'first_workout', 'rank_gold', 'rank_platinum']));
    expect(await db.getSetting(rankLadderVersionKey), '2');

    // Second run is a no-op.
    const better = AchievementStats(bestExerciseTierIndex: 9);
    expect(await migrateRankLadder(db: db, stats: better, defs: defs, now: now), isEmpty);
  });
}
