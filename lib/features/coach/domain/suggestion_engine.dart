import 'dart:math' as math;

import '../../../core/domain/equipment.dart';
import '../../../core/domain/training.dart';
import '../../readiness/domain/readiness.dart';

/// An active progression freeze caused by an ego flag.
class FreezeState {
  const FreezeState({required this.until, required this.baseWeight});
  final DateTime until;

  /// Top working weight when the freeze started; suggestions sit 5 % below it.
  final double baseWeight;

  bool isActive(DateTime now) => now.isBefore(until);

  int daysLeft(DateTime now) {
    if (!isActive(now)) return 0;
    return (until.difference(now).inHours / 24).ceil();
  }
}

/// Readiness as seen by one exercise (after the training-load modifier).
class ExerciseReadiness {
  const ExerciseReadiness({
    required this.score,
    required this.calibrating,
    this.loadPenaltyGroups = const [],
  });

  /// Neutral (60) when calibrating or data is missing, before the load penalty.
  final int score;
  final bool calibrating;

  /// Group labels that triggered the −10 training-load modifier.
  final List<String> loadPenaltyGroups;

  static const neutral = ExerciseReadiness(score: ReadinessCalculator.neutralScore, calibrating: false);

  int get adjustedScore =>
      loadPenaltyGroups.isEmpty ? score : score - ReadinessCalculator.loadPenalty;

  ReadinessBand get band => ReadinessCalculator.bandFor(adjustedScore);
}

class SuggestionInput {
  const SuggestionInput({
    required this.range,
    required this.targetSets,
    required this.targetRir,
    required this.increment,
    required this.equipment,
    required this.history,
    required this.readiness,
    required this.now,
    this.freeze,
    this.bodyweight = 0,
    this.assisted = false,
    this.rangeMatched = true,
  });

  final RepRange range;
  final int targetSets;
  final int targetRir;
  final double increment;
  final EquipmentKind equipment;

  /// Finished sessions of this exercise, oldest first.
  final List<ExerciseSessionLog> history;
  final ExerciseReadiness readiness;
  final DateTime now;
  final FreezeState? freeze;

  /// For bodyweight-loaded exercises: percentage changes apply to bodyweight + weight.
  final double bodyweight;

  /// Assisted machines log assistance as negative weight (−25 = 25 kg of help).
  final bool assisted;

  /// False when none of [history] was done at [range] (e.g. imported 10–12 work for a 4–6 slot):
  /// the load is then re-anchored from the best e1RM of the last 3 sessions.
  final bool rangeMatched;
}

class Suggestion {
  const Suggestion({
    required this.kind,
    required this.weight,
    required this.reps,
    required this.sets,
    required this.rir,
    required this.headline,
    required this.why,
    this.techniqueDay = false,
    this.rampUp = false,
    this.band = ReadinessBand.green,
  });

  final SuggestionKind kind;
  final double weight;
  final int reps;
  final int sets;
  final int rir;
  final String headline;
  final List<String> why;
  final bool techniqueDay;

  /// Calibration: ramp the weight up across sets instead of a fixed load.
  final bool rampUp;
  final ReadinessBand band;
}

/// Loads as the lifter reads them. Multiples of 0.25 kg (plates, micro-plates) show exactly;
/// anything else (pound conversions from the Liftoff import, stored at full precision) is
/// rounded to the nearest 0.5 kg for display.
String formatKg(double kg) {
  final quarters = kg * 4;
  if ((quarters - quarters.roundToDouble()).abs() > 1e-6) kg = (kg * 2).roundToDouble() / 2;
  if (kg == kg.roundToDouble()) return kg.toStringAsFixed(0);
  final s = kg.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String formatRpe(double rpe) => rpe == rpe.roundToDouble() ? rpe.toStringAsFixed(0) : rpe.toStringAsFixed(1);

/// Double progression + readiness modifiers + ego freeze.
class SuggestionEngine {
  const SuggestionEngine();

  static const double maxIncreaseFraction = 0.05;
  static const double failureReduction = 0.05;
  static const double plateauReduction = 0.10;
  static const double redReduction = 0.10;
  static const double freezeReduction = 0.05;
  static const double calibrationStopRpe = 8;

  Suggestion suggest(SuggestionInput input) {
    final all = input.history.where((l) => l.hasWorkingSets).toList();
    if (all.isEmpty) return _calibration(input);
    // Readiness is applied after progression, so a Red technique day (load cut for recovery,
    // not performance) is not the progression base. Use the last normal session instead.
    final normal = all.where((l) => !l.techniqueDay).toList();
    final logs = normal.isEmpty ? all : normal;

    final last = logs.last;
    final why = <String>[_describe('Last session', last)];
    final inc = input.increment;
    final range = input.range;

    SuggestionKind kind;
    double weight;
    int reps;
    final lastTop = last.topWeight;

    if (last.suggestionKind == SuggestionKind.calibration || !input.rangeMatched) {
      final recent = logs.sublist(math.max(0, logs.length - 3));
      final best = recent.map((l) => _bestSet(l, input.bodyweight)).reduce(
          (a, b) => b.e1rm(bodyweight: input.bodyweight) > a.e1rm(bodyweight: input.bodyweight) ? b : a);
      final e1rm = best.e1rm(bodyweight: input.bodyweight);
      weight = floorToIncrement(e1rm / (1 + (range.min + input.targetRir) / 30) - input.bodyweight, inc);
      weight = math.max(weight, _minLoad(input));
      reps = range.min;
      kind = SuggestionKind.seeded;
      why.add(last.suggestionKind == SuggestionKind.calibration
          ? 'Calibration best set ${formatKg(best.weight)} kg × ${best.reps} @ RPE ${formatRpe(best.effectiveRpe)} '
              '→ e1RM ${e1rm.toStringAsFixed(1)} kg. Working weight for ${range.min} reps at ${input.targetRir} RIR.'
          : 'No recent sets at $range. Best of the last ${recent.length} session(s): ${_loadText(best.weight)} × ${best.reps} '
              '@ RPE ${formatRpe(best.effectiveRpe)} → e1RM ${e1rm.toStringAsFixed(1)} kg, '
              'so ${_loadText(weight)} for ${range.min} reps at ${input.targetRir} RIR.');
    } else {
      final working = last.workingSets;
      // Effort is judged against the prescription: going to failure is never a failed set, only
      // missing the bottom of the range is. The top of the range only counts if it was reached
      // without going past the prescribed reps in reserve.
      final maxRpe = 10.0 - input.targetRir;
      final failed = working.any((s) => s.reps < range.min);
      final allTop = working.every((s) => s.reps >= range.max && s.effectiveRpe <= maxRpe);
      final topSets = last.topSets;
      final minTopReps = topSets.map((s) => s.reps).reduce(math.min);

      if (failed) {
        kind = SuggestionKind.reduce;
        weight = _scaled(input, lastTop, 1 - failureReduction);
        if (weight >= lastTop) weight = _lowered(input, lastTop);
        reps = range.min;
        why.add('A working set fell below $range reps → weight −5% '
            '(${formatKg(lastTop)} → ${formatKg(weight)} kg), target ${range.min} reps.');
      } else if (allTop) {
        kind = SuggestionKind.increase;
        // Exactly one increment up from what was lifted (cable stacks and dumbbells aren't on a
        // 2.5 kg grid, so snapping to it would turn +2.5 into +3.5).
        weight = snapNoise(lastTop + inc);
        reps = range.min;
        why.add('All working sets hit the top of $range at the prescribed effort '
            '(${input.targetRir == 0 ? 'failure' : 'RPE ≤ ${formatRpe(maxRpe)}'}) → +${formatKg(weight - lastTop)} kg, '
            'reps reset to ${range.min}.');
      } else if (_isPlateau(logs)) {
        kind = SuggestionKind.plateauDeload;
        weight = _scaled(input, lastTop, 1 - plateauReduction);
        if (weight >= lastTop) weight = _lowered(input, lastTop);
        reps = math.max(range.min, math.min(range.max, minTopReps));
        why.add('Plateau: two sessions in a row without progress (same weight, no extra reps, RPE not lower) '
            '→ one lighter session at −10%, then rebuild.');
      } else {
        kind = SuggestionKind.addReps;
        weight = lastTop;
        reps = math.min(range.max, minTopReps + 1);
        why.add(minTopReps >= range.max
            ? 'Top of $range reached but past the prescribed effort → same weight, own the reps.'
            : 'Within $range → same weight, beat last time\'s reps on at least one set.');
      }
    }

    var sets = input.targetSets;

    // Ego freeze overrides progression.
    final freeze = input.freeze;
    if (freeze != null && freeze.isActive(input.now)) {
      final frozen = _scaled(input, freeze.baseWeight, 1 - freezeReduction);
      weight = math.min(weight, frozen);
      kind = SuggestionKind.egoFreeze;
      reps = range.min;
      why.add('Ego flag: progression frozen for ${freeze.daysLeft(input.now)} more day(s) '
          '→ 5% below ${formatKg(freeze.baseWeight)} kg.');
    }

    // Readiness modifier.
    final r = input.readiness;
    final band = r.band;
    var technique = false;
    if (r.loadPenaltyGroups.isNotEmpty) {
      why.add('${r.loadPenaltyGroups.join(', ')} volume over the last 7 days is above 1.5× your 4-week average '
          '→ readiness −${ReadinessCalculator.loadPenalty} for this exercise.');
    }
    final scoreText = r.calibrating ? 'calibrating, treated as Green' : '${r.adjustedScore}';
    switch (band) {
      case ReadinessBand.green:
        why.add('Readiness ${band.label} ($scoreText) → no change.');
      case ReadinessBand.yellow:
        if (weight > lastTop) {
          weight = lastTop;
          reps = math.min(range.max, math.max(range.min, last.topSets.map((s) => s.reps).reduce(math.min)));
          if (kind == SuggestionKind.increase) kind = SuggestionKind.addReps;
          why.add('Readiness ${band.label} ($scoreText) → no weight increase today, holding ${formatKg(weight)} kg.');
        } else {
          why.add('Readiness ${band.label} ($scoreText) → no increase planned anyway; sets unchanged.');
        }
      case ReadinessBand.red:
        final before = weight;
        weight = _scaled(input, weight, 1 - redReduction);
        sets = math.max(1, sets - 1);
        technique = true;
        why.add('Readiness ${band.label} ($scoreText) → technique day: '
            '${formatKg(before)} → ${formatKg(weight)} kg (−10%) and one fewer working set.');
    }

    weight = snapNoise(weight);
    return Suggestion(
      kind: kind,
      weight: weight,
      reps: reps,
      sets: sets,
      rir: input.targetRir,
      techniqueDay: technique,
      band: band,
      headline: _headline(weight, reps, sets, input.targetRir, technique, input.equipment),
      why: why,
    );
  }

  Suggestion _calibration(SuggestionInput input) {
    // Assisted machines start with about half of bodyweight as assistance.
    final start = input.assisted
        ? floorToIncrement(-input.bodyweight * 0.5, input.increment)
        : startingWeight(input.equipment, input.increment);
    final r = input.readiness;
    var sets = input.targetSets;
    var technique = false;
    final why = <String>[
      'No history for this exercise → calibration session.',
      'Start at ${_loadText(start)} and add weight each set while form stays clean. '
          'Stop every set at RPE ${formatRpe(calibrationStopRpe)} (2 reps left).',
      'Your best working set today seeds future suggestions.',
    ];
    if (r.band == ReadinessBand.red) {
      sets = math.max(1, sets - 1);
      technique = true;
      why.add('Readiness Red (${r.adjustedScore}) → one fewer set, keep it light.');
    }
    final loadText = _loadText(start);
    return Suggestion(
      kind: SuggestionKind.calibration,
      weight: start,
      reps: input.range.min,
      sets: sets,
      rir: 2,
      rampUp: true,
      techniqueDay: technique,
      band: r.band,
      headline: 'Calibration: start at $loadText and ramp up, $sets sets, stop each set at RPE 8',
      why: why,
    );
  }

  static String _headline(double w, int reps, int sets, int rir, bool technique, EquipmentKind eq) {
    final load = (w == 0 && eq == EquipmentKind.bodyweight) ? 'Bodyweight' : (w < 0 ? '${formatKg(-w)} kg assistance' : '${formatKg(w)} kg');
    final core = '$load × $reps, $sets ${sets == 1 ? 'set' : 'sets'}, stop at $rir reps in reserve';
    return technique ? 'Technique day: $core' : 'Today: $core';
  }

  /// [weight] scaled by [factor] on the effective load (bodyweight + weight for bodyweight-loaded
  /// lifts), floored to the increment. Never below the lightest allowed load.
  static double _scaled(SuggestionInput input, double weight, double factor) {
    final bw = input.bodyweight;
    final scaled = floorToIncrement((weight + bw) * factor - bw, input.increment);
    return math.max(_minLoad(input), scaled);
  }

  /// One increment lighter (for loads too small for a percentage to move them).
  static double _lowered(SuggestionInput input, double weight) => math.max(_minLoad(input), weight - input.increment);

  /// Plain lifts can't go below 0 kg; assisted lifts can add assistance down to full bodyweight.
  static double _minLoad(SuggestionInput input) => input.assisted ? -input.bodyweight : 0;

  static String _loadText(double w) => w == 0 ? 'bodyweight' : (w < 0 ? '${formatKg(-w)} kg assistance' : '${formatKg(w)} kg');

  static LoggedSet _bestSet(ExerciseSessionLog log, double bodyweight) {
    LoggedSet best = log.workingSets.first;
    for (final s in log.workingSets) {
      if (s.e1rm(bodyweight: bodyweight) > best.e1rm(bodyweight: bodyweight)) best = s;
    }
    return best;
  }

  /// Two consecutive sessions without progress over the last three logs.
  static bool _isPlateau(List<ExerciseSessionLog> logs) {
    if (logs.length < 3) return false;
    final a = logs[logs.length - 3], b = logs[logs.length - 2], c = logs.last;
    if (b.suggestionKind == SuggestionKind.plateauDeload || c.suggestionKind == SuggestionKind.plateauDeload) {
      return false;
    }
    return _noProgress(a, b) && _noProgress(b, c);
  }

  static bool _noProgress(ExerciseSessionLog prev, ExerciseSessionLog cur) {
    if (cur.topWeight != prev.topWeight) return false;
    final prevReps = prev.topSets.fold<int>(0, (s, x) => s + x.reps);
    final curReps = cur.topSets.fold<int>(0, (s, x) => s + x.reps);
    if (curReps > prevReps) return false;
    return _avgRpe(cur) >= _avgRpe(prev);
  }

  static double _avgRpe(ExerciseSessionLog l) {
    final t = l.topSets;
    return t.fold<double>(0, (s, x) => s + x.effectiveRpe) / t.length;
  }

  static String _describe(String label, ExerciseSessionLog log) {
    final w = log.workingSets;
    final weights = w.map((s) => s.weight).toSet();
    final reps = w.map((s) => s.reps).join(', ');
    final rpes = w.map((s) => s.rpe == null ? '–' : formatRpe(s.rpe!)).join(', ');
    final load = weights.length == 1
        ? '${formatKg(weights.first)} kg × $reps'
        : w.map((s) => '${formatKg(s.weight)}×${s.reps}').join(', ');
    final d = log.date;
    return '$label (${d.day}/${d.month}): $load @ RPE $rpes.';
  }
}
