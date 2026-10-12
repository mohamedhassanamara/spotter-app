import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/providers.dart';
import 'edb_budget.dart';
import 'edb_client.dart';

final edbBudgetStoreProvider = Provider((ref) => EdbBudgetStore(ref.watch(databaseProvider)));

/// The V2 client. Tests override this with a fake; no real calls in CI.
final edbApiProvider = Provider<EdbApi>(
  (ref) => EdbV2Client(client: http.Client(), store: ref.watch(edbBudgetStoreProvider), clock: ref.watch(clockProvider)),
);

/// This month's usage, live.
final edbBudgetProvider = StreamProvider<EdbBudget>((ref) {
  final now = ref.watch(clockProvider);
  return ref.watch(databaseProvider).watchSettings().map((m) => EdbBudget.decode(m[EdbBudgetStore.budgetKey], now()));
});

final edbLogProvider = FutureProvider.autoDispose<List<EdbLogEntry>>((ref) {
  ref.watch(edbBudgetProvider);
  return ref.watch(edbBudgetStoreProvider).log();
});
