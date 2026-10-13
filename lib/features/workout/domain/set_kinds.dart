import '../../../core/db/database.dart';

/// Section 6 set types. Working and warm-up sets are the classic rows; the rest are technique follow-ups
/// that hang under a working set: drop sets (lighter, to failure, no rest), myo-rep cycles (same load,
/// 5 s rest, 2 reps) and the weighted static hold (same load, held for seconds; `reps` stores seconds).
enum SetKind {
  working('working', '', 'Working set'),
  warmup('warmup', 'W', 'Warm-up'),
  drop('drop', 'D', 'Drop set'),
  myo('myo', 'M', 'Myo-rep cycle'),
  hold('hold', 'H', 'Static hold');

  const SetKind(this.id, this.letter, this.label);
  final String id;
  final String letter;
  final String label;

  bool get isFollowUp => this == drop || this == myo || this == hold;

  /// Stored in `workout_sets.set_type` (null for working and warm-up sets).
  String? get setType => isFollowUp ? id : null;

  static SetKind of({required bool isWarmup, String? setType}) => switch (setType) {
        'drop' => drop,
        'myo' => myo,
        'hold' => hold,
        _ => isWarmup ? warmup : working,
      };

  static SetKind fromId(String id) => values.firstWhere((k) => k.id == id, orElse: () => working);
}

extension WorkoutSetKind on WorkoutSet {
  SetKind get kind => SetKind.of(isWarmup: isWarmup, setType: setType);

  /// Drop, myo or hold: never a working set of its own (no numbering, progression, ranks or PRs).
  bool get isFollowUp => kind.isFollowUp;

  /// A numbered working set.
  bool get isWorkingSet => kind == SetKind.working;
}

/// Myo-reps: rest between cycles and reps per cycle (program technique `myo_reps`).
const int myoRestSeconds = 5;
const int myoRepsPerCycle = 2;

/// Weighted static hold (program technique `weighted_static_hold_30s`).
const int holdSeconds = 30;

/// Default drop when the set isn't a program drop-set technique (the program's is 25 %).
const int defaultDropPct = 20;

/// Drop-set load: [from] minus [pct] %, rounded to the equipment [increment], always at least one
/// increment lighter and never below zero (assisted lifts: more assistance, i.e. more negative).
double dropWeight(double from, {required int pct, required double increment}) {
  final inc = increment <= 0 ? 1.0 : increment;
  if (from < 0) {
    // Assisted: a "drop" adds assistance.
    final raw = from - from.abs() * pct / 100;
    final r = (raw / inc).round() * inc;
    return r >= from ? from - inc : r;
  }
  final raw = from * (1 - pct / 100);
  var r = (raw / inc).round() * inc;
  if (r >= from) r = from - inc;
  return r < 0 ? 0 : double.parse(r.toStringAsFixed(2));
}

/// Program technique ids (assets/programs/min_max_phase2.json) and what each pre-creates under the
/// last working set: two drops at 25 %, one myo-rep cycle (more can be added), one 30 s hold.
const String dropTechnique = 'drop_sets_2x25';
const String myoTechnique = 'myo_reps';
const String holdTechnique = 'weighted_static_hold_30s';
const int programDropPct = 25;
const int programDrops = 2;

/// Follow-ups a program technique creates, in order.
List<SetKind> followUpsFor(String? technique) => switch (technique) {
      dropTechnique => const [SetKind.drop, SetKind.drop],
      myoTechnique => const [SetKind.myo],
      holdTechnique => const [SetKind.hold],
      _ => const [],
    };
