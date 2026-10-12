/// The 6 body regions and 20 muscles used for ranking, volume, the body graph and the training-load
/// modifier (Liftoff's structure).
enum BodyRegion {
  arms('Arms'),
  legs('Legs'),
  core('Core'),
  shoulders('Shoulders'),
  chest('Chest'),
  back('Back');

  const BodyRegion(this.label);
  final String label;

  List<Muscle> get muscles => [for (final m in Muscle.values) if (m.region == this) m];

  static BodyRegion? fromName(String name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

enum Muscle {
  biceps('Biceps', BodyRegion.arms, 'biceps'),
  triceps('Triceps', BodyRegion.arms, 'triceps'),
  forearms('Forearms', BodyRegion.arms, 'forearms'),
  quadriceps('Quadriceps', BodyRegion.legs, 'quadriceps'),
  hamstrings('Hamstrings', BodyRegion.legs, 'hamstrings'),
  glutes('Glutes', BodyRegion.legs, 'glutes'),
  calves('Calves', BodyRegion.legs, 'calves'),
  adductors('Adductors', BodyRegion.legs, 'adductors'),
  abductors('Abductors', BodyRegion.legs, 'abductors'),
  abdominals('Abdominals', BodyRegion.core, 'abdominals'),
  obliques('Obliques', BodyRegion.core, 'obliques'),
  frontDelt('Front Delt', BodyRegion.shoulders, 'front_delt'),
  middleDelt('Middle Delt', BodyRegion.shoulders, 'middle_delt'),
  rearDelt('Rear Delt', BodyRegion.shoulders, 'rear_delt'),
  upperChest('Upper Chest', BodyRegion.chest, 'upper_chest'),
  lowerChest('Lower Chest', BodyRegion.chest, 'lower_chest'),
  lats('Lats', BodyRegion.back, 'lats'),
  upperBack('Upper Back', BodyRegion.back, 'upper_back'),
  traps('Traps', BodyRegion.back, 'traps'),
  lowerBack('Lower Back', BodyRegion.back, 'lower_back');

  const Muscle(this.label, this.region, this.key);
  final String label;
  final BodyRegion region;

  /// snake_case id used in assets/exercise_muscles.json and deep links.
  final String key;

  static Muscle? fromKey(String key) {
    for (final m in values) {
      if (m.key == key || m.name == key) return m;
    }
    return null;
  }
}

/// How much an exercise trains each muscle, 0–1 (1.0 = prime mover).
class MuscleTargets {
  const MuscleTargets(this.weights);

  final Map<Muscle, double> weights;

  static const empty = MuscleTargets({});

  /// Weight ≥ 0.5: counts for volume, the training-load modifier and quests.
  static const double primaryThreshold = 0.5;

  Set<Muscle> get primary => {for (final e in weights.entries) if (e.value >= primaryThreshold) e.key};
  Set<Muscle> get secondary => {for (final e in weights.entries) if (e.value > 0 && e.value < primaryThreshold) e.key};

  Set<BodyRegion> get primaryRegions => {for (final m in primary) m.region};

  bool get isEmpty => weights.isEmpty;

  bool trains(Muscle m) => (weights[m] ?? 0) > 0;

  double weightFor(Muscle m) => weights[m] ?? 0;

  /// Muscles by weight, strongest first.
  List<MapEntry<Muscle, double>> get ranked => weights.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}
