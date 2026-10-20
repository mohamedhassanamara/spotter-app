import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/gamification/data/gamification_repository.dart';
import 'package:spotter/features/gamification/domain/achievements.dart';
import 'package:spotter/features/ranks/data/ladder_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 12);

  test('v7 silently retires achievements that are gone, revokes rank ones the ladder no longer supports, unlocks what is met, runs once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.putSetting(rankLadderVersionKey, '2');
    final repo = GamificationRepository(db);
    final defs = await GamificationRepository.loadAchievementDefs();
    // Earned under the old model: old rank badges, the "follow the coach" ones, a lift badge that the new ladder doesn't give,
    // and achievements that carry over.
    await repo.unlock(
      ['rank_silver', 'rank_master', 'patience', 'monk_mode', 'disciplined', 'comeback', 'lift_diamond', 'first_workout', 'first_pr'],
      DateTime(2026, 10, 1),
    );

    // On the new ladder the best lift is Platinum (index 4); 124 workouts.
    const stats = AchievementStats(bestExerciseTierIndex: 4, sessions: 124, prs: 1);
    final r = await migrateRankLadder(db: db, stats: stats, defs: defs, now: now);
    expect(r.revoked.toSet(), {'rank_silver', 'rank_master', 'patience', 'monk_mode', 'disciplined', 'comeback', 'lift_diamond'});
    expect(await repo.unlockedKeys(), {'first_workout', 'first_pr', 'lift_silver', 'lift_gold', 'lift_platinum', 'sessions_25', 'sessions_100'});
    expect(await db.getSetting(rankLadderVersionKey), '$rankLadderVersion');

    // Second run is a no-op.
    const better = AchievementStats(bestExerciseTierIndex: 8);
    final again = await migrateRankLadder(db: db, stats: better, defs: defs, now: now);
    expect(again.unlocked, isEmpty);
    expect(again.revoked, isEmpty);
  });

  test('also unlocks achievements the new ladder qualifies for', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final defs = await GamificationRepository.loadAchievementDefs();
    final r = await migrateRankLadder(db: db, stats: const AchievementStats(bestExerciseTierIndex: 3), defs: defs, now: now);
    expect(r.unlocked.toSet(), {'lift_silver', 'lift_gold'});
  });

  test('without a bodyweight nothing is revoked and the migration stays pending', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = GamificationRepository(db);
    await repo.unlock(['rank_master', 'patience'], DateTime(2026, 10, 1));
    final defs = await GamificationRepository.loadAchievementDefs();
    final r = await migrateRankLadder(db: db, stats: const AchievementStats(bestExerciseTierIndex: -1), defs: defs, now: now, ranksKnown: false);
    expect(r.revoked, isEmpty);
    expect(await repo.unlockedKeys(), {'rank_master', 'patience'});
    expect(await db.getSetting(rankLadderVersionKey), isNull);
  });

  test('v8 renames the top lift achievements silently: old Immortal is Olympian, old Radiant is Immortal, once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.putSetting(rankLadderVersionKey, '7');
    final repo = GamificationRepository(db);
    final defs = await GamificationRepository.loadAchievementDefs();
    await repo.unlock(['lift_immortal', 'lift_radiant'], DateTime(2026, 10, 1));
    // Pending without a bodyweight: the rename still happens, exactly once.
    await migrateRankLadder(db: db, stats: const AchievementStats(bestExerciseTierIndex: -1), defs: defs, now: now, ranksKnown: false);
    await migrateRankLadder(db: db, stats: const AchievementStats(bestExerciseTierIndex: -1), defs: defs, now: now, ranksKnown: false);
    expect(await repo.unlockedKeys(), {'lift_olympian', 'lift_immortal'});
    expect((await repo.watchUnlocked().first)['lift_immortal'], DateTime(2026, 10, 1), reason: 'keeps the date');
  });
}
