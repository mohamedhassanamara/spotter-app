import 'dart:convert';

import '../../library/domain/exercise_info.dart';
import '../../library/domain/name_resolver.dart';

/// How a Liftoff exercise name was mapped to a library exercise, most to least trusted.
enum MatchMethod {
  manual('Picked'),
  override('Name map'),
  routine('My routine'),
  exact('Exact'),
  fuzzy('Fuzzy'),
  custom('New custom'),
  unmatched('Unmatched');

  const MatchMethod(this.label);
  final String label;
}

/// A custom exercise to create for a Liftoff name the library has no equivalent for.
class CustomSpec {
  const CustomSpec({required this.name, this.primaryMuscles = const [], this.secondaryMuscles = const [], this.equipment, this.compound = false});
  final String name;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final String? equipment;
  final bool compound;

  factory CustomSpec.fromJson(Map<String, dynamic> j) => CustomSpec(
        name: j['name'] as String,
        primaryMuscles: (j['primaryMuscles'] as List? ?? const []).cast<String>(),
        secondaryMuscles: (j['secondaryMuscles'] as List? ?? const []).cast<String>(),
        equipment: j['equipment'] as String?,
        compound: j['compound'] as bool? ?? false,
      );
}

/// Stable id for the custom exercise created for a Liftoff name, so re-imports reuse it.
String liftoffCustomId(String liftoffName) =>
    'liftoff_${liftoffName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '')}';

/// One load band of a name that meant different equipment depending on the weight (Liftoff's
/// generic "Shoulder Press": machine at 80 kg and up, barbell below).
class WeightRule {
  const WeightRule({required this.minKg, required this.exerciseId, this.displayName});
  final double minKg;
  final String exerciseId;
  final String? displayName;
}

/// assets/liftoff_name_map.json. Values: a library id; `{"id", "exclude_from_ranks"}`;
/// `{"by_weight": [{"min_kg", "id", "name"}…]}`; or `{"custom": {…}}`.
class LiftoffNameMap {
  const LiftoffNameMap({this.ids = const {}, this.customs = const {}, this.excludeFromRanks = const {}, this.byWeight = const {}});
  final Map<String, String> ids;
  final Map<String, CustomSpec> customs;

  /// Liftoff names whose exercise is kept out of ranking (records stay).
  final Set<String> excludeFromRanks;

  /// Rules ordered heaviest band first; the last one has min_kg 0.
  final Map<String, List<WeightRule>> byWeight;

  static const empty = LiftoffNameMap();

  factory LiftoffNameMap.parse(String raw) {
    final map = (jsonDecode(raw) as Map<String, dynamic>)['map'] as Map<String, dynamic>;
    final ids = <String, String>{};
    final customs = <String, CustomSpec>{};
    final exclude = <String>{};
    final byWeight = <String, List<WeightRule>>{};
    map.forEach((name, v) {
      if (v is String) {
        ids[name] = v;
      } else if (v is Map<String, dynamic>) {
        if (v['custom'] is Map<String, dynamic>) {
          customs[name] = CustomSpec.fromJson(v['custom'] as Map<String, dynamic>);
        } else if (v['by_weight'] is List) {
          byWeight[name] = [
            for (final r in (v['by_weight'] as List).cast<Map<String, dynamic>>())
              WeightRule(minKg: (r['min_kg'] as num? ?? 0).toDouble(), exerciseId: r['id'] as String, displayName: r['name'] as String?),
          ]..sort((a, b) => b.minKg.compareTo(a.minKg));
        } else if (v['id'] is String) {
          ids[name] = v['id'] as String;
        }
        if (v['exclude_from_ranks'] == true) exclude.add(name);
      }
    });
    return LiftoffNameMap(ids: ids, customs: customs, excludeFromRanks: exclude, byWeight: byWeight);
  }
}

/// A routine exercise as the owner names it ("Chest Press" → Leverage_Chest_Press).
class RoutineName {
  const RoutineName({required this.name, required this.exerciseId});
  final String name;
  final String exerciseId;
}

class NameMapping {
  const NameMapping({
    required this.liftoffName,
    required this.method,
    required this.confidence,
    required this.sets,
    this.exerciseId,
    this.exerciseName,
    this.displayName,
    this.custom,
    this.weightRules = const [],
    this.excludeFromRanks = false,
  });

  final String liftoffName;
  final MatchMethod method;

  /// 0..1 (1 for name map, routine, exact and manual picks).
  final double confidence;

  /// Working sets in the file under this name.
  final int sets;
  final String? exerciseId;
  final String? exerciseName;

  /// Name to show in history: the routine's name when it came from a routine, else Liftoff's.
  final String? displayName;
  final CustomSpec? custom;

  /// When set, the exercise is chosen per session from its top weight ([exerciseId] is the lightest band).
  final List<WeightRule> weightRules;

  /// Imported with its exercise kept out of ranking.
  final bool excludeFromRanks;

  /// The exercise and display name for one session's sets of this name, by their top weight (kg).
  (String, String?) resolveFor(double topKg) {
    for (final r in weightRules) {
      if (topKg >= r.minKg) return (r.exerciseId, r.displayName ?? displayName);
    }
    return (exerciseId!, displayName);
  }

  bool get needsReview => method == MatchMethod.unmatched || (method == MatchMethod.fuzzy && confidence < 0.9);
}

/// "Assisted Pull-Ups" and "Assisted Pull Ups", "Triceps" and "Tricep" compare equal.
String nameKey(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.isNotEmpty)
    .map((t) => t.length > 3 && t.endsWith('s') && !t.endsWith('ss') ? t.substring(0, t.length - 1) : t)
    .join(' ');

/// Fuzzy matches below this are left for the owner to pick (or become custom exercises).
const double fuzzyAcceptScore = 0.8;

/// Maps every Liftoff name: manual pick → name map (id or custom) → routine name → exact library
/// name → fuzzy (≥ [fuzzyAcceptScore]) → unmatched.
List<NameMapping> mapLiftoffNames({
  required Map<String, int> setsByName,
  required Map<String, ExerciseInfo> catalog,
  LiftoffNameMap nameMap = LiftoffNameMap.empty,
  List<RoutineName> routines = const [],
  Map<String, String> manual = const {},
}) {
  final resolver = ExerciseNameResolver(catalog.values.where((e) => !e.isCustom || e.id.startsWith('liftoff_')));
  final byRoutineKey = {for (final r in routines) nameKey(r.name): r};
  final out = <NameMapping>[];
  for (final name in setsByName.keys.toList()..sort()) {
    final sets = setsByName[name]!;
    final exclude = nameMap.excludeFromRanks.contains(name);
    NameMapping found(String id, MatchMethod m, double c, {String? display}) => NameMapping(
          liftoffName: name,
          method: m,
          confidence: c,
          sets: sets,
          exerciseId: id,
          exerciseName: catalog[id]?.name ?? id,
          displayName: display ?? name,
          excludeFromRanks: exclude,
        );

    final picked = manual[name];
    if (picked != null && catalog.containsKey(picked)) {
      out.add(found(picked, MatchMethod.manual, 1));
      continue;
    }
    final rules = nameMap.byWeight[name];
    if (rules != null && rules.isNotEmpty && rules.every((r) => catalog.containsKey(r.exerciseId))) {
      final light = rules.last;
      out.add(NameMapping(
        liftoffName: name,
        method: MatchMethod.override,
        confidence: 1,
        sets: sets,
        exerciseId: light.exerciseId,
        exerciseName: [
          for (final r in rules) '${catalog[r.exerciseId]!.name}${r.minKg > 0 ? ' (≥ ${r.minKg.round()} kg)' : ''}',
        ].join(' / '),
        displayName: light.displayName ?? name,
        weightRules: rules,
        excludeFromRanks: exclude,
      ));
      continue;
    }
    final mapped = nameMap.ids[name];
    if (mapped != null && catalog.containsKey(mapped)) {
      final r = byRoutineKey[nameKey(name)];
      out.add(found(mapped, MatchMethod.override, 1, display: r != null && r.exerciseId == mapped ? r.name : null));
      continue;
    }
    final custom = nameMap.customs[name];
    if (custom != null) {
      final id = liftoffCustomId(name);
      out.add(NameMapping(
        liftoffName: name,
        method: MatchMethod.custom,
        confidence: 1,
        sets: sets,
        exerciseId: id,
        exerciseName: custom.name,
        displayName: name,
        custom: custom,
      ));
      continue;
    }
    final routine = byRoutineKey[nameKey(name)];
    if (routine != null && catalog.containsKey(routine.exerciseId)) {
      out.add(found(routine.exerciseId, MatchMethod.routine, 1, display: routine.name));
      continue;
    }
    final best = resolver.resolve(name, minScore: fuzzyAcceptScore);
    if (best != null) {
      final exact = nameKey(best.exercise.name) == nameKey(name);
      out.add(found(best.exercise.id, exact ? MatchMethod.exact : MatchMethod.fuzzy, best.score));
      continue;
    }
    // Nothing usable: imported as a custom exercise of the same name unless the owner picks one.
    out.add(NameMapping(
      liftoffName: name,
      method: MatchMethod.unmatched,
      confidence: resolver.candidates(name, limit: 1).firstOrNull?.score ?? 0,
      sets: sets,
      exerciseId: liftoffCustomId(name),
      exerciseName: name,
      displayName: name,
      custom: CustomSpec(name: name),
    ));
  }
  return out;
}
