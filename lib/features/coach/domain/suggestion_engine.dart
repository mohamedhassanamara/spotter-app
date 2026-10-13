import 'dart:math' as math;

import '../../../core/domain/equipment.dart';
import '../../../core/domain/gym.dart';
import '../../../core/domain/training.dart';
import '../../readiness/domain/readiness.dart';
import 'energy.dart';

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

/// "Form reset": you chose a lighter weight on purpose (to fix form). Progression restarts from
/// [weight] on [at]; older, heavier sessions no longer count (no reductions from them).
class FormReset {
  const FormReset({required this.weight, required this.at});
  final double weight;
  final DateTime at;
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
    this.grid,
    this.compound = false,
    this.fatigued = const [],
    this.energy = EnergyContext.none,
    this.formReset,
  });

  final RepRange range;
  final int targetSets;
  final int targetRir;

  /// Used only when no [grid] is given (a plain grid in this step from 0).
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

  /// The loads that exist for this exercise (Settings → My gym equipment + weights you've logged).
  final WeightGrid? grid;

  /// Compound lifts may drop one step on a Red day; isolations never go below last session.
  final bool compound;

  /// Prime-mover muscles that are Fatigued right now (muscle recovery).
  final List<String> fatigued;

  /// Bodyweight trend and nutrition from Apple Health.
  final EnergyContext energy;
  final FormReset? formReset;
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
    this.formResetHint,
  });

  final SuggestionKind kind;
  final double weight;
  final int reps;
  final int sets;
  final int rir;
  final String headline;

  /// The chain behind the number, one step per line, each starting with its stage:
  /// "Base:", "Rule:", "Readiness:", "Recovery:", "Nutrition:", "Weight:".
  final List<String> why;
  final bool techniqueDay;

  /// Calibration: ramp the weight up across sets instead of a fixed load.
  final bool rampUp;
  final ReadinessBand band;

  /// Set when the last session looks like a deliberate step down to fix form: the weight a
  /// "Form reset" would restart from.
  final double? formResetHint;
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

/// Double progression on the weights that exist, then readiness / recovery / nutrition, never more
/// than one step of softening, and no drop spirals. Every step is explained in [Suggestion.why].
class SuggestionEngine {
  const SuggestionEngine();

  static const double failureReduction = 0.05;
  static const double plateauReduction = 0.10;
  static const double freezeReduction = 0.05;
  static const double calibrationStopRpe = 8;

  /// A jump to the next available weight bigger than this (relative) waits for extended reps.
  static const double bigJump = 0.10;

  /// Extended rep target before a big jump: top of the range + 2 (aim up to + 3).
  static const int extendBy = 2;
  static const int extendMax = 3;

  /// Load decreases in a row allowed before the engine holds (ego flags excepted).
  static const int maxConsecutiveDrops = 2;

  /// Sessions after a jump during which falling short of the range means hold, not drop.
  static const int postJumpGrace = 2;

  Suggestion suggest(SuggestionInput input) {
    final grid = input.grid ?? _plainGrid(input);
    var all = input.history.where((l) => l.hasWorkingSets).toList();
    final reset = input.formReset;
    if (reset != null) all = [for (final l in all) if (!dateOnlyOf(l.date).isBefore(dateOnlyOf(reset.at))) l];
    if (all.isEmpty && reset == null) return _calibration(input, grid);

    // Readiness is applied after progression, so a small-deload day (load cut for recovery,
    // not performance) is not the progression base. Use the last normal session instead.
    final normal = all.where((l) => !l.techniqueDay).toList();
    final logs = normal.isEmpty ? all : normal;
    final range = input.range;
    final why = <String>[];
    final energy = input.energy;

    SuggestionKind kind;
    double weight;
    int reps;
    double lastTop;
    double? resetHint;

    if (logs.isEmpty) {
      // Form reset with nothing logged since: start from the reset weight.
      lastTop = reset!.weight;
      weight = reset.weight;
      reps = range.min;
      kind = SuggestionKind.seeded;
      why.add('Base: form reset on ${_d(reset.at)} at ${_loadText(reset.weight)}; nothing logged since.');
      why.add('Rule: progression restarts from the reset weight at ${range.min} reps.');
    } else {
      final last = logs.last;
      lastTop = last.topWeight;
      why.add('Base: ${_describe('last session', last)}${reset != null ? ' (since your form reset on ${_d(reset.at)})' : ''}');
      final drops = _consecutiveDrops(logs);

      if (last.suggestionKind == SuggestionKind.calibration || !input.rangeMatched) {
        final recent = logs.sublist(math.max(0, logs.length - 3));
        final best = recent.map((l) => _bestSet(l, input.bodyweight)).reduce(
            (a, b) => b.e1rm(bodyweight: input.bodyweight) > a.e1rm(bodyweight: input.bodyweight) ? b : a);
        final e1rm = best.e1rm(bodyweight: input.bodyweight);
        weight = e1rm / (1 + (range.min + input.targetRir) / 30) - input.bodyweight;
        reps = range.min;
        kind = SuggestionKind.seeded;
        why.add(last.suggestionKind == SuggestionKind.calibration
            ? 'Rule: calibration best set ${_loadText(best.weight)} × ${best.reps} @ RPE ${formatRpe(best.effectiveRpe)} '
                '→ e1RM ${e1rm.toStringAsFixed(1)} kg → ${formatKg(weight)} kg for ${range.min} reps at ${input.targetRir} RIR.'
            : 'Rule: no recent sets at $range. Best of the last ${recent.length} session(s): ${_loadText(best.weight)} × ${best.reps} '
                '@ RPE ${formatRpe(best.effectiveRpe)} → e1RM ${e1rm.toStringAsFixed(1)} kg → ${formatKg(weight)} kg for ${range.min} reps at ${input.targetRir} RIR.');
      } else {
        final working = last.workingSets;
        // Effort is judged against the prescription: going to failure is never a failed set, only
        // missing the bottom of the range is. The top only counts at the prescribed effort.
        final maxRpe = 10.0 - input.targetRir;
        final failed = working.any((s) => s.reps < range.min);
        final allTop = working.every((s) => s.reps >= range.max && s.effectiveRpe <= maxRpe);
        final minTopReps = last.topSets.map((s) => s.reps).reduce(math.min);
        final sessionsAtWeight = _trailingAtWeight(logs);
        final before = logs.length > sessionsAtWeight ? logs[logs.length - sessionsAtWeight - 1].topWeight : null;
        final justJumped = before != null && before < lastTop - 0.01 && sessionsAtWeight <= postJumpGrace;

        if (failed) {
          final drop = _reduced(input, grid, lastTop, failureReduction);
          if (justJumped) {
            kind = SuggestionKind.addReps;
            weight = lastTop;
            reps = range.min;
            why.add('Rule: a set fell below $range, but this is session $sessionsAtWeight at ${_loadText(lastTop)} after a jump '
                '→ hold the weight and build back into the range (no drop).');
          } else if (energy.deficit) {
            kind = SuggestionKind.addReps;
            weight = lastTop;
            reps = range.min;
            why.add('Rule: a set fell below $range, but you\'re in a deficit (${energy.deficitReason}) where a stall is expected '
                '→ hold ${_loadText(lastTop)} instead of dropping.');
          } else if (drops >= maxConsecutiveDrops && !_frozen(input)) {
            kind = SuggestionKind.addReps;
            weight = lastTop;
            reps = range.min;
            why.add('Rule: a set fell below $range, but the load already went down $drops sessions in a row '
                '→ hold ${_loadText(lastTop)} (no third drop).');
          } else {
            kind = SuggestionKind.reduce;
            weight = drop;
            reps = range.min;
            why.add('Rule: a working set fell below $range → −5 % on the next available weight '
                '(${_loadText(lastTop)} → ${_loadText(weight)}), target ${range.min} reps.');
          }
        } else if (allTop) {
          final next = grid.next(lastTop);
          final jump = grid.nextJump(lastTop, bodyweight: input.bodyweight);
          final target = range.max + extendBy;
          if (next == null) {
            kind = SuggestionKind.addReps;
            weight = lastTop;
            reps = math.min(range.max + extendMax, minTopReps + 1);
            why.add('Rule: top of $range, but ${_loadText(lastTop)} is the heaviest you have → keep it and add reps.');
          } else if (jump != null && jump > bigJump && minTopReps < target) {
            kind = SuggestionKind.addReps;
            weight = lastTop;
            reps = math.min(range.max + extendMax, math.max(range.max + 1, minTopReps + 1));
            why.add('Rule: top of $range, but the next weight (${_loadText(next)}) is +${(jump * 100).round()} % '
                '→ extend to $target–${range.max + extendMax} reps at ${_loadText(lastTop)} before jumping.');
          } else {
            kind = SuggestionKind.increase;
            weight = next;
            reps = range.min;
            why.add('Rule: all working sets hit the top of $range at the prescribed effort '
                '(${input.targetRir == 0 ? 'failure' : 'RPE ≤ ${formatRpe(maxRpe)}'})${jump != null && jump > bigJump ? ' and the extended reps' : ''} '
                '→ next available weight ${_loadText(next)}, reps reset to ${range.min}.');
          }
        } else if (_isPlateau(logs, energy.deficit ? 3 : 2)) {
          if (drops >= maxConsecutiveDrops && !_frozen(input)) {
            kind = SuggestionKind.addReps;
            weight = lastTop;
            reps = math.max(range.min, math.min(range.max, minTopReps));
            why.add('Rule: plateau, but the load already went down $drops sessions in a row → hold.');
          } else {
            kind = SuggestionKind.plateauDeload;
            weight = _reduced(input, grid, lastTop, plateauReduction);
            reps = math.max(range.min, math.min(range.max, minTopReps));
            why.add('Rule: plateau: ${energy.deficit ? 'three' : 'two'} sessions in a row without progress '
                '→ one lighter session (${_loadText(weight)}, about −10 %), then rebuild.');
          }
        } else {
          kind = SuggestionKind.addReps;
          weight = lastTop;
          reps = math.min(range.max, minTopReps + 1);
          why.add(minTopReps >= range.max
              ? 'Rule: top of $range reached but past the prescribed effort → same weight, own the reps.'
              : 'Rule: within $range → same weight, beat last time\'s reps on at least one set.');
        }

        // A deliberate step down at the top of the range looks like a form reset.
        final previous = logs.length > 1 ? logs.sublist(math.max(0, logs.length - 4), logs.length - 1) : const <ExerciseSessionLog>[];
        final prevBest = previous.isEmpty ? null : previous.map((l) => l.topWeight).reduce(math.max);
        final hitTop = last.topSets.any((s) => s.reps >= range.max);
        if (prevBest != null && grid.previous(prevBest) != null && lastTop <= grid.previous(prevBest)! + 0.01 && hitTop && !last.techniqueDay) {
          resetHint = lastTop;
          why.add('Form reset? You went from ${_loadText(prevBest)} to ${_loadText(lastTop)} and hit ${range.max}+ reps. If that was on purpose, '
              'use Form reset so progression starts from ${_loadText(lastTop)} and the heavier sessions stop counting.');
        }
      }
    }

    // The routine's set count is never changed by any coaching input.
    final sets = input.targetSets;
    // "Repeat" means last session's top weight for its best reps at that weight, kept inside the range
    // (up to the extended target) so a short session never becomes today's goal.
    final repeatReps = logs.isEmpty
        ? range.min
        : logs.last.topSets.map((s) => s.reps).reduce(math.max).clamp(range.min, range.max + extendMax).toInt();

    // Ego freeze overrides progression.
    final freeze = input.freeze;
    if (freeze != null && freeze.isActive(input.now)) {
      final frozen = grid.snapDown((freeze.baseWeight + input.bodyweight) * (1 - freezeReduction) - input.bodyweight);
      weight = math.min(weight, frozen);
      kind = SuggestionKind.egoFreeze;
      reps = range.min;
      why.add('Rule: ego flag, progression frozen for ${freeze.daysLeft(input.now)} more day(s) '
          '→ 5 % below ${formatKg(freeze.baseWeight)} kg.');
    }

    // Readiness + recovery adjust the target, never the volume: "repeat" (last session's weight and
    // reps, no progression) or a "small deload" (one available step down, same reps). One step at
    // most in total; isolations never below last session.
    final r = input.readiness;
    final band = r.band;
    var deloadDay = false;
    var adjustment = '';
    if (r.loadPenaltyGroups.isNotEmpty) {
      why.add('Readiness: ${r.loadPenaltyGroups.join(', ')} volume over the last 7 days is above 1.5× your 4-week average '
          '→ readiness −${ReadinessCalculator.loadPenalty} for this exercise.');
    }
    final scoreText = r.calibrating ? 'calibrating, treated as Green' : '${r.adjustedScore}';
    final fatigued = input.fatigued.isNotEmpty;
    final cause = [
      if (band != ReadinessBand.green) 'Readiness ${band.label} ($scoreText)',
      if (fatigued) '${input.fatigued.map((m) => m.toLowerCase()).join(', ')} Fatigued',
    ].join(' + ');
    if (!fatigued && band == ReadinessBand.green) {
      why.add('Readiness: Green ($scoreText) → no change.');
    } else if (band == ReadinessBand.red && input.compound && weight >= lastTop - 0.01) {
      // Small deload: one available step below last session, same rep target, every set.
      final down = grid.previous(lastTop);
      weight = down == null ? lastTop : math.max(down, _minLoad(input));
      reps = repeatReps.clamp(range.min, range.max).toInt();
      if (kind == SuggestionKind.increase) kind = SuggestionKind.addReps;
      deloadDay = true;
      adjustment = 'Small deload';
      why.add('Readiness: $cause → small deload: ${_loadText(weight)} × $reps (one step down from ${_loadText(lastTop)}), all $sets sets.');
    } else if (weight >= lastTop - 0.01) {
      weight = lastTop;
      reps = repeatReps;
      if (kind == SuggestionKind.increase) kind = SuggestionKind.addReps;
      adjustment = 'Repeat';
      why.add('${band == ReadinessBand.green ? 'Recovery' : 'Readiness'}: $cause → repeat last session (${_loadText(weight)} × $reps), all $sets sets.');
    } else {
      why.add('${band == ReadinessBand.green ? 'Recovery' : 'Readiness'}: $cause → no extra change: the progression rule already '
          'lowered today\'s load to ${_loadText(weight)}${input.compound ? '' : ' (isolations never go lower for readiness)'}.');
    }

    // Nutrition: modest, transparent, never a reason to add load.
    if (!energy.hasNutrition && energy.trend == null) {
      why.add('Nutrition: no nutrition or bodyweight trend data in Apple Health, so it isn\'t used.');
    } else {
      if (energy.deficit) {
        why.add('Nutrition: deficit (${energy.deficitReason}): stalls are expected, so falling short holds instead of dropping, and plateaus need three flat sessions.');
      } else if (energy.trend != null) {
        why.add('Nutrition: bodyweight ${energy.trend!.label}${energy.hasNutrition ? '' : ' (no food logged in Health)'} → no effect.');
      }
      if (energy.lowProtein) {
        why.add('Nutrition: protein ${energy.proteinPerKg!.toStringAsFixed(1)} g/kg over the last 7 days is under ${EnergyConfig.lowProteinPerKg} g/kg; loads unchanged.');
      }
    }

    // No drop spirals: never a third decrease in a row (ego flags excepted).
    if (logs.isNotEmpty && weight < lastTop - 0.01 && _consecutiveDrops(logs) >= maxConsecutiveDrops && !_frozen(input)) {
      weight = lastTop;
      why.add('Rule: the load already went down ${_consecutiveDrops(logs)} sessions in a row → holding ${_loadText(lastTop)}.');
    }

    // Only weights that exist.
    weight = math.max(weight, _minLoad(input));
    final exact = weight;
    weight = grid.contains(exact) ? grid.snap(exact) : grid.snapDown(exact);
    if (weight < _minLoad(input)) weight = grid.snapUp(_minLoad(input));
    why.add(grid.contains(exact)
        ? 'Weight: ${_loadText(weight)} exists in your gym.'
        : 'Weight: ${formatKg(exact)} kg isn\'t available → ${_loadText(weight)} (the next lighter one you have).');

    return Suggestion(
      kind: kind,
      weight: weight,
      reps: reps,
      sets: sets,
      rir: input.targetRir,
      techniqueDay: deloadDay,
      band: band,
      headline: _headline(weight, reps, sets, input.targetRir, adjustment, input.equipment),
      why: why,
      formResetHint: resetHint,
    );
  }

  Suggestion _calibration(SuggestionInput input, WeightGrid grid) {
    // Assisted machines start with about half of bodyweight as assistance.
    final raw = input.assisted ? -input.bodyweight * 0.5 : startingWeight(input.equipment, input.increment);
    final start = input.assisted ? grid.snapDown(raw) : grid.snapUp(raw);
    final r = input.readiness;
    final sets = input.targetSets;
    final why = <String>[
      'Base: no history for this exercise → calibration session.',
      'Rule: start at ${_loadText(start)} and add weight each set while form stays clean. '
          'Stop every set at RPE ${formatRpe(calibrationStopRpe)} (2 reps left). Your best working set today seeds future suggestions.',
    ];
    if (r.band == ReadinessBand.red) {
      why.add('Readiness: Red (${r.adjustedScore}) → ramp up conservatively; all $sets sets.');
    }
    why.add('Weight: ${_loadText(start)} is the lightest you have for it.');
    final loadText = _loadText(start);
    return Suggestion(
      kind: SuggestionKind.calibration,
      weight: start,
      reps: input.range.min,
      sets: sets,
      rir: 2,
      rampUp: true,
      band: r.band,
      headline: 'Calibration: start at $loadText and ramp up, $sets sets, stop each set at RPE 8',
      why: why,
    );
  }

  /// "Today: …", or "Repeat: …" / "Small deload: …" when readiness or recovery adjusted the target.
  static String _headline(double w, int reps, int sets, int rir, String adjustment, EquipmentKind eq) {
    final load = (w == 0 && eq == EquipmentKind.bodyweight) ? 'Bodyweight' : (w < 0 ? '${formatKg(-w)} kg assistance' : '${formatKg(w)} kg');
    final core = '$load × $reps, $sets ${sets == 1 ? 'set' : 'sets'}, stop at $rir reps in reserve';
    return '${adjustment.isEmpty ? 'Today' : adjustment}: $core';
  }

  /// When no gym grid is given: every multiple of the increment (and every logged weight).
  static WeightGrid _plainGrid(SuggestionInput input) {
    final inc = input.increment <= 0 ? 2.5 : input.increment;
    final lo = input.assisted ? -(input.bodyweight <= 0 ? 150 : input.bodyweight) : 0.0;
    return WeightGrid([
      for (var w = lo; w <= 400; w += inc) (w * 1000).roundToDouble() / 1000,
      for (final l in input.history) for (final s in l.sets) snapNoise(s.weight),
    ]);
  }

  /// [lastTop] reduced by [fraction] on the effective load, on the next available lighter weight
  /// (always at least one step lighter).
  static double _reduced(SuggestionInput input, WeightGrid grid, double lastTop, double fraction) {
    final bw = input.bodyweight;
    var w = grid.snapDown((lastTop + bw) * (1 - fraction) - bw);
    if (w >= lastTop - 0.01) w = grid.previous(lastTop) ?? lastTop;
    return math.max(w, _minLoad(input));
  }

  static bool _frozen(SuggestionInput input) => input.freeze != null && input.freeze!.isActive(input.now);

  /// Sessions in a row (ending with the last) whose top weight went down from the one before.
  static int _consecutiveDrops(List<ExerciseSessionLog> logs) {
    var n = 0;
    for (var i = logs.length - 1; i > 0; i--) {
      if (logs[i].topWeight < logs[i - 1].topWeight - 0.01) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  /// How many sessions in a row (ending with the last) were at the last session's top weight.
  static int _trailingAtWeight(List<ExerciseSessionLog> logs) {
    final w = logs.last.topWeight;
    var n = 0;
    for (var i = logs.length - 1; i >= 0 && (logs[i].topWeight - w).abs() < 0.01; i--) {
      n++;
    }
    return n;
  }

  /// Plain lifts can't go below 0 kg; assisted lifts can add assistance down to full bodyweight.
  static double _minLoad(SuggestionInput input) => input.assisted ? -input.bodyweight : 0;

  static String _loadText(double w) => w == 0 ? 'bodyweight' : (w < 0 ? '${formatKg(-w)} kg assistance' : '${formatKg(w)} kg');

  static String _d(DateTime d) => '${d.day}/${d.month}';

  static LoggedSet _bestSet(ExerciseSessionLog log, double bodyweight) {
    LoggedSet best = log.workingSets.first;
    for (final s in log.workingSets) {
      if (s.e1rm(bodyweight: bodyweight) > best.e1rm(bodyweight: bodyweight)) best = s;
    }
    return best;
  }

  /// [pairs] consecutive sessions without progress over the last [pairs] + 1 logs.
  static bool _isPlateau(List<ExerciseSessionLog> logs, int pairs) {
    if (logs.length < pairs + 1) return false;
    final tail = logs.sublist(logs.length - pairs - 1);
    if (tail.skip(1).any((l) => l.suggestionKind == SuggestionKind.plateauDeload)) return false;
    for (var i = 1; i < tail.length; i++) {
      if (!_noProgress(tail[i - 1], tail[i])) return false;
    }
    return true;
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

DateTime dateOnlyOf(DateTime d) => DateTime(d.year, d.month, d.day);
