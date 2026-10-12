import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/database.dart';
import 'core/providers.dart';
import 'features/library/data/exercise_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final db = AppDatabase.open();
  await ExerciseRepository(db).ensureSeeded();

  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const SpotterApp(),
  ));
}
