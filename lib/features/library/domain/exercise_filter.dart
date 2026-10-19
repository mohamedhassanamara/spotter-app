import 'exercise_aliases.dart';
import 'exercise_info.dart';

/// Library search and filters.
class ExerciseFilter {
  const ExerciseFilter({this.query = '', this.muscle, this.equipment, this.favoritesOnly = false});

  final String query;

  /// A dataset muscle name (e.g. "lats").
  final String? muscle;

  /// A dataset equipment value; "none" matches exercises with no equipment listed.
  final String? equipment;
  final bool favoritesOnly;

  static const noEquipment = 'none';

  bool get isActive => query.isNotEmpty || muscle != null || equipment != null || favoritesOnly;

  ExerciseFilter copyWith({String? query, String? Function()? muscle, String? Function()? equipment, bool? favoritesOnly}) =>
      ExerciseFilter(
        query: query ?? this.query,
        muscle: muscle != null ? muscle() : this.muscle,
        equipment: equipment != null ? equipment() : this.equipment,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      );

  /// [aliases]: other names of each exercise (see [buildAliases]); a search also matches those.
  bool matches(ExerciseInfo e, {Map<String, Set<String>> aliases = const {}}) {
    if (favoritesOnly && !e.isFavorite) return false;
    if (muscle != null && !e.primaryMuscles.contains(muscle) && !e.secondaryMuscles.contains(muscle)) return false;
    if (equipment != null) {
      final eq = e.equipment ?? noEquipment;
      if (eq != equipment) return false;
    }
    if (query.isNotEmpty && searchTokens(query).isNotEmpty) {
      // Each name on its own (a word of one name never combines with a word of another):
      // "high to low", "high-to-low" and "hightolow" all find "High-to-Low Cable Fly".
      if (![e.name, ...?aliases[e.id]].any((n) => searchMatches(n, query))) return false;
    }
    return true;
  }

  /// The other name that made [e] match the search, when its own name did not ("High-to-Low Cable Fly" for Cable Crossover).
  String? matchedAlias(ExerciseInfo e, Map<String, Set<String>> aliases) {
    if (searchTokens(query).isEmpty || searchMatches(e.name, query)) return null;
    for (final a in aliases[e.id] ?? const <String>{}) {
      if (searchMatches(a, query)) return a;
    }
    return null;
  }

  /// Filters and orders: favorites first, then name; primary-muscle matches before secondary.
  List<ExerciseInfo> apply(Iterable<ExerciseInfo> all, {Map<String, Set<String>> aliases = const {}}) {
    final out = all.where((e) => matches(e, aliases: aliases)).toList();
    int rank(ExerciseInfo e) {
      var r = 0;
      if (!e.isFavorite) r += 2;
      if (muscle != null && !e.primaryMuscles.contains(muscle)) r += 1;
      return r;
    }

    out.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }
}
