import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/db/database.dart';
import '../../../core/domain/dates.dart';
import '../domain/achievements.dart';
import '../domain/quests.dart';

/// Minutes slept per night, by day (yyyy-MM-dd), from the Health data synced so far.
Map<String, double> sleepByDayRows(Iterable<DailyMetric> days) => {for (final d in days) if (d.sleepMinutes != null) d.date: d.sleepMinutes!};

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

  // ---- weekly challenges ----

  Stream<List<StoredQuest>> watchQuests(DateTime week) => (_db.select(_db.quests)
        ..where((t) => t.weekStart.equals(dayKey(weekStart(week))))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .watch()
      .map(_toStoredList);

  Future<List<StoredQuest>> quests(DateTime week) async => _toStoredList(await (_db.select(_db.quests)
        ..where((t) => t.weekStart.equals(dayKey(weekStart(week))))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get());

  /// Challenges whose kind this version no longer has (the retired "follow the coach" ones) are skipped.
  List<StoredQuest> _toStoredList(List<Quest> rows) => [
        for (final q in rows)
          if (QuestDef.tryFromParams(q.key, jsonDecode(q.params) as Map<String, dynamic>) case final def?) StoredQuest(row: q, def: def),
      ];

  /// [QuestDef.id]s of the week before [week]'s challenges, so they are not picked again.
  Future<Set<String>> previousQuestIds(DateTime week) async =>
      {for (final q in await quests(addDays(weekStart(week), -7))) q.def.id};

  /// Removes the retired "follow every suggestion" challenges, from any week (they rewarded following the coach).
  Future<int> retireSuggestionQuests() =>
      (_db.delete(_db.quests)..where((t) => t.key.isIn(retiredQuestKeys))).go();

  /// Makes sure this week has three challenges: creates them the first time the app looks at the week, and tops the
  /// week up when retired ones were removed. [generate] gets the kinds already present.
  Future<void> ensureQuests(DateTime week, List<QuestDef> Function(Set<QuestKey> existing, int missing) generate) async {
    final key = dayKey(weekStart(week));
    await _db.transaction(() async {
      await retireSuggestionQuests();
      final existing = _toStoredList(await (_db.select(_db.quests)..where((t) => t.weekStart.equals(key))).get());
      if (existing.length >= 3) return;
      for (final q in generate({for (final e in existing) e.def.key}, 3 - existing.length)) {
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
