import '../../library/domain/exercise_info.dart';
import '../../ranks/domain/ranks.dart';
import '../../tutorials/domain/gif_rule.dart';
import '../../tutorials/domain/media_matcher.dart';

/// [variant]: the same movement with a modifier the ranking entry does not name (a decline crunch ranked as a crunch). Kept, shown for review.
enum StandardVerdict { ok, none, variant, mismatch }

/// The ranking entry a logged exercise is scored against must be the same movement on the same equipment as the exercise.
StandardVerdict standardVerdict({required ExerciseInfo exercise, required StrengthStandard? standard}) {
  if (standard == null) return StandardVerdict.none;
  final a = coreNouns(exercise.name), b = coreNouns(standard.name);
  if (a.isNotEmpty && b.isNotEmpty && a.intersection(b).isEmpty) return StandardVerdict.mismatch;
  final tokens = MediaMatcher.normalizeTokens(standard.name).toSet();
  final wanted = <String>{
    if (tokens.contains('dumbbell')) 'dumbbell',
    if (tokens.contains('barbell')) 'barbell',
    if (tokens.contains('cable')) 'cable',
    if (tokens.contains('smith') || tokens.contains('machine') || tokens.contains('lever') || tokens.contains('leverage')) 'machine',
  };
  final have = (exercise.equipment ?? '').toLowerCase();
  if (wanted.isNotEmpty && have.isNotEmpty && have != 'other' && have != 'body only') {
    final ok = switch (have) {
      'barbell' || 'e-z curl bar' => wanted.contains('barbell'),
      'dumbbell' => wanted.contains('dumbbell'),
      'cable' => wanted.contains('cable'),
      'machine' => wanted.contains('machine'),
      _ => true,
    };
    if (!ok) return StandardVerdict.mismatch;
  }
  // A per-hand standard (dumbbell rows, curls) is one arm at a time by definition.
  final diff = modifierDiff(exercise.name, standard.name);
  if (standard.perHand) diff.remove('unilateral');
  return diff.isEmpty ? StandardVerdict.ok : StandardVerdict.variant;
}

class AuditRow {
  const AuditRow({
    required this.exercise,
    required this.names,
    required this.nameSource,
    required this.gifName,
    required this.gifEquipments,
    required this.gifSource,
    required this.gif,
    required this.standardName,
    required this.standard,
    required this.inRoutines,
    required this.setCount,
  });

  final ExerciseInfo exercise;

  /// The names this exercise carries in my routines and sessions (the owner's name, e.g. from Liftoff), besides the library's.
  final List<String> names;

  /// library | merged (library entry is the canonical of a merged duplicate) | custom | imported (a Liftoff name mapped onto it)
  final String nameSource;
  final String? gifName;
  final List<String> gifEquipments;
  final String? gifSource;
  final GifVerdict gif;
  final String? standardName;
  final StandardVerdict standard;
  final bool inRoutines;
  final int setCount;

  bool get hasIssue => gif == GifVerdict.wrongEquipment || gif == GifVerdict.wrongMovement || standard == StandardVerdict.mismatch;

  bool get isVariant => standard == StandardVerdict.variant;

  List<String> get issues => [
        if (gif == GifVerdict.wrongEquipment) 'GIF "$gifName" is ${gifEquipments.join('/')}, the exercise is ${exercise.equipment}',
        if (gif == GifVerdict.wrongMovement) 'GIF "$gifName" is a different movement',
        if (standard == StandardVerdict.variant) 'ranked as "$standardName", a variant of it (kept)',
        if (standard == StandardVerdict.mismatch) 'ranked as "$standardName", a different movement or equipment',
      ];
}

/// One row per exercise I use. [matches] maps an exercise id to its stored GIF row; [namesById] are the owner's names for each exercise.
List<AuditRow> auditExercises({
  required Iterable<String> usedIds,
  required Set<String> routineIds,
  required Map<String, int> setCounts,
  required Map<String, ExerciseInfo> catalog,
  required Map<String, ({String? edbId, String source})> matches,
  required Map<String, Set<String>> namesById,
  required Map<String, String> mergedCanonicals,
  required List<EdbExercise> edb,
  required List<StrengthStandard> standards,
}) {
  final matcher = MediaMatcher(edb);
  final byEdb = {for (final e in edb) e.id: e};
  final standardOf = {for (final s in standards) for (final id in s.exerciseIds) id: s};
  final rows = <AuditRow>[];
  for (final id in usedIds.toSet()) {
    final ex = catalog[id];
    if (ex == null) continue;
    final m = matches[id];
    final g = m?.edbId == null ? null : byEdb[m!.edbId];
    final std = standardOf[id];
    final names = (namesById[id] ?? const <String>{}).where((n) => n != ex.name).toList()..sort();
    rows.add(AuditRow(
      exercise: ex,
      names: names,
      nameSource: ex.isCustom
          ? 'custom'
          : mergedCanonicals.containsKey(id)
              ? 'merged'
              : names.isNotEmpty
                  ? 'imported'
                  : 'library',
      gifName: g?.name,
      gifEquipments: g?.equipments ?? const [],
      gifSource: m?.source,
      gif: g == null ? GifVerdict.noGif : gifVerdict(name: ex.name, equipment: ex.equipment, edb: g, matcher: matcher),
      standardName: std?.name,
      standard: standardVerdict(exercise: ex, standard: std),
      inRoutines: routineIds.contains(id),
      setCount: setCounts[id] ?? 0,
    ));
  }
  rows.sort((a, b) {
    final c = (b.inRoutines ? 1 : 0).compareTo(a.inRoutines ? 1 : 0);
    return c != 0 ? c : a.exercise.name.compareTo(b.exercise.name);
  });
  return rows;
}
