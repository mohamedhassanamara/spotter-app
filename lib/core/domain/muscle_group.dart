/// The 12 muscle groups used for ranking, volume and the body graph.
enum MuscleGroup {
  chest('Chest'),
  back('Back'),
  shoulders('Shoulders'),
  biceps('Biceps'),
  triceps('Triceps'),
  forearms('Forearms'),
  abs('Abs'),
  quads('Quads'),
  hamstrings('Hamstrings'),
  glutes('Glutes'),
  calves('Calves'),
  traps('Traps');

  const MuscleGroup(this.label);
  final String label;

  static MuscleGroup? fromName(String name) {
    for (final g in values) {
      if (g.name == name) return g;
    }
    return null;
  }
}

/// Which ranking groups an exercise trains, split by role.
class MuscleTargets {
  const MuscleTargets({required this.primary, required this.secondary});

  final Set<MuscleGroup> primary;

  /// Secondary groups, never overlapping with [primary].
  final Set<MuscleGroup> secondary;

  static const empty = MuscleTargets(primary: {}, secondary: {});

  bool trains(MuscleGroup g) => primary.contains(g) || secondary.contains(g);

  /// Contribution weight of this exercise to a group: primary 1.0, secondary 0.3.
  double weightFor(MuscleGroup g) {
    if (primary.contains(g)) return 1.0;
    if (secondary.contains(g)) return 0.3;
    return 0.0;
  }
}
