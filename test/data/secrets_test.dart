import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Defence in depth next to .githooks/pre-commit: no tracked file may contain the RapidAPI key, and
/// config/secrets.json itself must stay git-ignored.
void main() {
  final secrets = File('config/secrets.json');

  test('config/secrets.json is git-ignored', () {
    final r = Process.runSync('git', ['check-ignore', '-q', 'config/secrets.json']);
    expect(r.exitCode, 0);
  });

  test('no tracked file contains the key', () {
    final key = (jsonDecode(secrets.readAsStringSync()) as Map<String, dynamic>)['EDB_RAPIDAPI_KEY'] as String? ?? '';
    expect(key, isNotEmpty);
    final r = Process.runSync('git', ['grep', '-l', '-F', '-e', key]);
    expect(r.exitCode, 1, reason: 'git grep found the key in: ${r.stdout}');
  }, skip: secrets.existsSync() ? false : 'no config/secrets.json in this checkout');
}
