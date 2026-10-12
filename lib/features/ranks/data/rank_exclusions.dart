import 'dart:convert';

import '../../../core/db/database.dart';

/// Exercises the owner removed from ranking ("hide from ranks", like Liftoff). Their sets stay in
/// history and count for PRs and volume; they just never feed a muscle, region or overall rank.
class RankExclusions {
  RankExclusions(this._db);
  final AppDatabase _db;

  static const key = 'rank_excluded_exercises';

  static Set<String> decode(String? raw) => raw == null ? {} : {...(jsonDecode(raw) as List<dynamic>).cast<String>()};

  Future<Set<String>> load() async => decode(await _db.getSetting(key));

  Stream<Set<String>> watch() => _db.watchSettings().map((m) => decode(m[key]));

  Future<void> _save(Set<String> ids) => _db.putSetting(key, jsonEncode(ids.toList()..sort()));

  Future<void> addAll(Iterable<String> ids) async => _save({...await load(), ...ids});

  Future<void> set(String id, {required bool excluded}) async {
    final cur = await load();
    excluded ? cur.add(id) : cur.remove(id);
    await _save(cur);
  }
}
