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
    this.extraImages = const [],
    this.source,
    this.edbV1Id,
    this.credits = const [],
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

  /// Full image URLs from other free sources (wger), shown after the free-exercise-db photos.
  final List<String> extraImages;

  /// fedb | wger | edb_v1 | custom (null for older rows: free-exercise-db).
  final String? source;

  /// Its own ExerciseDB V1 GIF, when it came from (or was merged with) a V1 entry.
  final String? edbV1Id;

  /// Licence/author credits of the merged sources, e.g. {source: wger.de, license: CC-BY-SA 4.0, author}.
  final List<Map<String, dynamic>> credits;

  final MuscleTargets targets;
  final EquipmentKind equipmentKind;

  /// Compounds default to 6–10 reps, everything else to 10–15.
  bool get isCompound => mechanic == 'compound';

  /// free-exercise-db photos first, then other sources' images.
  List<String> get imageUrls => [for (final p in images) p.startsWith('http') ? p : '$exerciseImageBaseUrl$p', ...extraImages];

  RepRange defaultRange({RepRange compound = RepRange.compound, RepRange isolation = RepRange.isolation}) =>
      isCompound ? compound : isolation;


  String get muscleSummary {
    final all = [...primaryMuscles, ...secondaryMuscles];
    return all.isEmpty ? 'No muscles listed' : all.take(3).join(', ');
  }
}
