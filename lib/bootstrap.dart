import 'package:flutter/services.dart' show rootBundle;

import 'core/db/database.dart';
import 'features/library/data/exercise_repository.dart';
import 'features/library/domain/muscle_mapping.dart';
import 'features/program/data/program_repository.dart';
import 'features/tutorials/data/edb_v2/edb_mapping_repository.dart';

/// Work that must finish before the first frame (shared by main() and the integration tests): the
/// muscle contributions table, the exercise catalogue, then the owner's program routines.
Future<void> bootstrapDatabase(AppDatabase db) async {
  if (!ExerciseMuscleTable.isLoaded) ExerciseMuscleTable.load(await rootBundle.loadString('assets/exercise_muscles.json'));
  await ExerciseRepository(db).ensureSeeded();
  await ProgramRepository.ensureMyRoutinesInstalled(db);
  // ExerciseDB V2 mappings survive a reinstall through the bundled asset.
  await EdbMappingRepository(db).seedFromAsset(await rootBundle.loadString(EdbMappingRepository.assetPath), now: DateTime.now());
}
