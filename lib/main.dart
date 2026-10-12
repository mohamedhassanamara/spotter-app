import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/database.dart';
import 'core/diagnostics/error_log.dart';
import 'core/providers.dart';
import 'bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErrorLog.instance.init();
  ErrorLog.instance.installGlobalHandlers();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final db = AppDatabase.open();
  await bootstrapDatabase(db);

  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const SpotterApp(),
  ));
}
