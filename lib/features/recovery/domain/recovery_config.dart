import '../../../core/domain/muscles.dart';
import '../../../core/domain/training.dart';

/// Every constant of the muscle-recovery model in one place. These are a heuristic chosen to give
/// plausible numbers for a hypertrophy program, not measurements; see docs/DECISIONS.md.
abstract final class RecoveryConfig {
  /// Fatigue a working set adds per unit of muscle contribution, by effort.
  static const Map<Effort, double> effortFactor = {
    Effort.failure: 1.0,
    Effort.oneLeft: 0.85,
    Effort.twoLeft: 0.7,
    Effort.threePlus: 0.5,
  };

  /// A set logged without effort (imported history) counts as failure: the lifter trains to failure.
  static const Effort unknownEffort = Effort.failure;

  /// Drop sets and myo-rep cycles: half a set each, whatever the effort. Static holds likewise.
  static const double dropFactor = 0.5;
  static const double myoFactor = 0.5;
  static const double holdFactor = 0.5;

  /// Recovery half-life in hours.
  static const double largeHalfLifeH = 48;
  static const double smallHalfLifeH = 30;

  static const Set<Muscle> large = {
    Muscle.quadriceps,
    Muscle.hamstrings,
    Muscle.glutes,
    Muscle.lats,
    Muscle.upperBack,
    Muscle.upperChest,
    Muscle.lowerChest,
  };

  /// Muscles not in either list in the brief (adductors, abductors, lower back, obliques) use the
  /// small half-life; adductors/abductors and lower back recover like the small groups at these volumes.
  static double halfLifeH(Muscle m) => large.contains(m) ? largeHalfLifeH : smallHalfLifeH;

  /// Today's readiness band → recovery speed (Green normal).
  static const Map<String, double> readinessSpeed = {'green': 1.0, 'yellow': 0.85, 'red': 0.7};

  /// Fatigue (in failure-set equivalents × contribution) that means 0 % recovered. 12 ≈ a hard,
  /// high-volume session for one muscle; 6 hard sets right after training → 50 %.
  static const double fullFatigue = 12;

  /// Bands, in recovery %.
  static const double readyAt = 90;
  static const double recoveringAt = 60;

  /// Sets older than this are ignored (their residual is negligible).
  static const Duration horizon = Duration(days: 14);

  /// A session "hit" a muscle when it gave it at least this much fatigue (for "last session").
  static const double hitThreshold = 0.5;
}
