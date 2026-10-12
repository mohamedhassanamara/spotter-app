import 'core/db/database.dart';
import 'features/library/data/exercise_repository.dart';
import 'features/program/data/program_repository.dart';

/// Database work that must finish before the first frame (shared by main() and the integration
/// tests): the exercise catalogue, then the owner's program routines.
Future<void> bootstrapDatabase(AppDatabase db) async {
  await ExerciseRepository(db).ensureSeeded();
  await ProgramRepository.ensureMyRoutinesInstalled(db);
}
