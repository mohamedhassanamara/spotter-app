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

  bool matches(ExerciseInfo e) {
    if (favoritesOnly && !e.isFavorite) return false;
    if (muscle != null && !e.primaryMuscles.contains(muscle) && !e.secondaryMuscles.contains(muscle)) return false;
    if (equipment != null) {
      final eq = e.equipment ?? noEquipment;
      if (eq != equipment) return false;
    }
    if (query.isNotEmpty) {
      final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      final name = e.name.toLowerCase();
      if (!words.every(name.contains)) return false;
    }
    return true;
  }

  /// Filters and orders: favorites first, then name; primary-muscle matches before secondary.
  List<ExerciseInfo> apply(Iterable<ExerciseInfo> all) {
    final out = all.where(matches).toList();
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
