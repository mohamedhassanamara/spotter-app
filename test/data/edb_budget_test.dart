import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/tutorials/data/edb_v2/edb_budget.dart';
import 'package:spotter/features/tutorials/data/edb_v2/edb_client.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final oct = DateTime(2026, 10, 12, 9);

  group('budget guard', () {
    test('counts calls; soft warning at 1,500; hard stop at 1,850', () {
      var b = EdbBudget(month: '2026-10', localCount: 1499);
      expect(b.warn, isFalse);
      b = b.record(oct);
      expect(b.used, 1500);
      expect(b.warn, isTrue);
      expect(b.allows(oct), isTrue);
      b = EdbBudget(month: '2026-10', localCount: 1850);
      expect(b.stopped, isTrue);
      expect(b.allows(oct), isFalse);
      expect(b.resumesOn(), DateTime(2026, 11));
    });

    test('resets on the 1st of the next month', () {
      final b = EdbBudget(month: '2026-10', localCount: 1900);
      expect(b.allows(DateTime(2026, 10, 31, 23, 59)), isFalse);
      expect(b.allows(DateTime(2026, 11, 1, 0, 1)), isTrue);
      expect(b.record(DateTime(2026, 11, 1)).used, 1);
      expect(EdbBudget(month: '2026-12', localCount: 5).current(DateTime(2027, 1, 2)).used, 0);
    });

    test("RapidAPI's rate-limit headers win over the local count", () {
      var b = EdbBudget(month: '2026-10', localCount: 10);
      b = b.record(oct, headers: {'x-ratelimit-requests-limit': '2000', 'x-ratelimit-requests-remaining': '120'});
      expect(b.fromHeaders, isTrue);
      expect(b.used, 1880);
      expect(b.allows(oct), isFalse, reason: 'the server says we are past the hard stop');
      // A later response without headers keeps the server's last figures.
      expect(b.record(oct).used, 1880);
    });

    test('survives a restart (persisted as a setting)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = EdbBudgetStore(db);
      await store.save(EdbBudget(month: '2026-10', localCount: 42));
      expect((await store.load(oct)).used, 42);
      expect((await store.load(DateTime(2026, 11, 2))).used, 0);
    });
  });

  group('client', () {
    late AppDatabase db;
    late EdbBudgetStore store;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = EdbBudgetStore(db);
    });
    tearDown(() => db.close());

    test('sends the RapidAPI headers, counts the call and parses the search', () async {
      late http.Request seen;
      final client = EdbV2Client(
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'success': true, 'data': [{'exerciseId': 'exr_1', 'name': 'Bench Press', 'imageUrl': ''}]}), 200,
              headers: {'x-ratelimit-requests-limit': '2000', 'x-ratelimit-requests-remaining': '1990'});
        }),
        store: store,
        apiKey: 'test-key',
        clock: () => oct,
      );
      final hits = await client.search('bench press');
      expect(hits.single.exerciseId, 'exr_1');
      expect(seen.headers['X-RapidAPI-Key'], 'test-key');
      expect(seen.headers['X-RapidAPI-Host'], edbHost);
      expect(seen.url.queryParameters['search'], 'bench press');
      expect((await store.load(oct)).used, 10);
      final log = await store.log();
      expect(log.single.detail, contains('/api/v1/exercises/search'));
      expect(log.single.detail, isNot(contains('test-key')));
    });

    test('hard stop: no request is made; 401/403/429 are fallback errors', () async {
      await store.save(EdbBudget(month: '2026-10', localCount: 1850));
      var calls = 0;
      final client = EdbV2Client(client: MockClient((_) async => http.Response('{}', 200).also(() => calls++)), store: store, apiKey: 'k', clock: () => oct);
      await expectLater(client.search('x'), throwsA(isA<EdbException>().having((e) => e.code, 'code', 'BUDGET').having((e) => e.fallsBack, 'fallsBack', true)));
      expect(calls, 0);

      await store.save(EdbBudget.fresh(oct));
      final limited = EdbV2Client(
        client: MockClient((_) async => http.Response(jsonEncode({'error': {'code': 'TOO_MANY_REQUESTS', 'message': 'slow down'}}), 429)),
        store: store,
        apiKey: 'k',
        clock: () => oct,
      );
      await expectLater(limited.exercise('exr_1'), throwsA(isA<EdbException>().having((e) => e.status, 'status', 429).having((e) => e.fallsBack, 'fallsBack', true)));
    });

    test('without a key nothing is sent', () async {
      final client = EdbV2Client(client: MockClient((_) async => throw StateError('must not call')), store: store, apiKey: '');
      await expectLater(client.search('x'), throwsA(isA<EdbException>().having((e) => e.code, 'code', 'NO_KEY')));
    });
  });
}

extension<T> on T {
  T also(void Function() f) {
    f();
    return this;
  }
}
