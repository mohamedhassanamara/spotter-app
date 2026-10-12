import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/db/database.dart';
import '../../../core/domain/dates.dart';
import '../domain/achievements.dart';
import '../domain/quests.dart';

class StoredQuest {
  const StoredQuest({required this.row, required this.def});
  final Quest row;
  final QuestDef def;
}

class GamificationRepository {
  GamificationRepository(this._db);
  final AppDatabase _db;

  static List<AchievementDef>? _defsCache;

  static Future<List<AchievementDef>> loadAchievementDefs() async {
    if (_defsCache != null) return _defsCache!;
    final raw = jsonDecode(await rootBundle.loadString('assets/achievements.json')) as Map<String, dynamic>;
    return _defsCache = (raw['achievements'] as List<dynamic>)
        .map((e) => AchievementDef.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- XP ----

  Stream<int> watchTotalXp() {
    final sum = _db.xpEvents.amount.sum();
    return (_db.selectOnly(_db.xpEvents)..addColumns([sum])).watchSingle().map((r) => r.read(sum) ?? 0);
  }

  Future<int> totalXp() async {
    final sum = _db.xpEvents.amount.sum();
    final r = await (_db.selectOnly(_db.xpEvents)..addColumns([sum])).getSingle();
    return r.read(sum) ?? 0;
  }

  Future<void> addXp({required DateTime at, required int amount, required String reason, int? sessionId, DateTime? week}) async {
    if (amount == 0) return;
    await _db.into(_db.xpEvents).insert(XpEventsCompanion.insert(
          at: at,
          amount: amount,
          reason: reason,
          sessionId: Value(sessionId),
          weekStart: Value(week == null ? null : dayKey(week)),
        ));
  }

  Future<bool> hasWeeklyGoalBonus(DateTime week) async {
    final rows = await (_db.select(_db.xpEvents)
          ..where((t) => t.reason.equals('weekly_goal') & t.weekStart.equals(dayKey(week))))
        .get();
    return rows.isNotEmpty;
  }

  Future<List<XpEvent>> xpEvents() => (_db.select(_db.xpEvents)..orderBy([(t) => OrderingTerm.asc(t.at)])).get();

  // ---- achievements ----

  Stream<Map<String, DateTime>> watchUnlocked() =>
      _db.select(_db.achievementsUnlocked).watch().map((rows) => {for (final r in rows) r.key: r.unlockedAt});

  Future<Set<String>> unlockedKeys() async => (await _db.select(_db.achievementsUnlocked).get()).map((r) => r.key).toSet();

  /// Removes unlocked achievements (rank model migration only; nothing is shown to the lifter).
  Future<void> revoke(Iterable<String> keys) => (_db.delete(_db.achievementsUnlocked)..where((t) => t.key.isIn(keys))).go();

  Future<void> unlock(Iterable<String> keys, DateTime at) => _db.batch((b) {
        for (final k in keys) {
          b.insert(_db.achievementsUnlocked, AchievementsUnlockedCompanion.insert(key: k, unlockedAt: at),
              mode: InsertMode.insertOrIgnore);
        }
      });

  // ---- weekly quests ----

  Stream<List<StoredQuest>> watchQuests(DateTime week) => (_db.select(_db.quests)
        ..where((t) => t.weekStart.equals(dayKey(weekStart(week))))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .watch()
      .map((rows) => rows.map(_toStored).toList());

  Future<List<StoredQuest>> quests(DateTime week) async => (await (_db.select(_db.quests)
            ..where((t) => t.weekStart.equals(dayKey(weekStart(week))))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get())
      .map(_toStored)
      .toList();

  StoredQuest _toStored(Quest q) =>
      StoredQuest(row: q, def: QuestDef.fromParams(q.key, jsonDecode(q.params) as Map<String, dynamic>));

  /// Creates this week's quests once (the first time the app looks at the week).
  Future<void> ensureQuests(DateTime week, List<QuestDef> Function() generate) async {
    final key = dayKey(weekStart(week));
    await _db.transaction(() async {
      final existing = await (_db.select(_db.quests)..where((t) => t.weekStart.equals(key))).get();
      if (existing.isNotEmpty) return;
      for (final q in generate()) {
        await _db.into(_db.quests).insert(QuestsCompanion.insert(
              weekStart: key,
              key: q.key.name,
              params: Value(jsonEncode(q.toParams())),
              title: q.title,
            ));
      }
    });
  }

  Future<void> completeQuest(int id, DateTime at) =>
      (_db.update(_db.quests)..where((t) => t.id.equals(id))).write(QuestsCompanion(completedAt: Value(at)));
}
