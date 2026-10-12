import '../../../core/domain/equipment.dart';
import '../../../core/domain/muscles.dart';
import '../../../core/domain/training.dart';
import 'muscle_mapping.dart';

const String exerciseImageBaseUrl = 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/';

/// Pure view of an exercise from the catalogue.
class ExerciseInfo {
  ExerciseInfo({
    required this.id,
    required this.name,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    required this.equipment,
    required this.level,
    required this.mechanic,
    required this.category,
    required this.instructions,
    required this.images,
    required this.isCustom,
    required this.isFavorite,
    required this.notes,
  })  : targets = targetsFor(id, name, primaryMuscles, secondaryMuscles),
        equipmentKind = EquipmentKind.fromDataset(equipment);

  final String id;
  final String name;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final String? equipment;
  final String? level;
  final String? mechanic;
  final String? category;
  final List<String> instructions;
  final List<String> images;
  final bool isCustom;
  final bool isFavorite;
  final String? notes;

  final MuscleTargets targets;
  final EquipmentKind equipmentKind;

  /// Compounds default to 6–10 reps, everything else to 10–15.
  bool get isCompound => mechanic == 'compound';

  List<String> get imageUrls => [for (final p in images) '$exerciseImageBaseUrl$p'];

  RepRange defaultRange({RepRange compound = RepRange.compound, RepRange isolation = RepRange.isolation}) =>
      isCompound ? compound : isolation;

  /// YouTube search link, never a hard-coded video.
  Uri get formTutorialUri => Uri.https('www.youtube.com', '/results', {'search_query': '$name proper form'});

  String get muscleSummary {
    final all = [...primaryMuscles, ...secondaryMuscles];
    return all.isEmpty ? 'No muscles listed' : all.take(3).join(', ');
  }
}
