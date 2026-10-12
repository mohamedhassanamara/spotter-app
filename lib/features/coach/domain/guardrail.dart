import '../../../core/domain/training.dart';

enum OverrideReason {
  feltStrong('Felt strong'),
  testingMax('Testing a max'),
  justDidIt('Just did it');

  const OverrideReason(this.label);
  final String label;

  static OverrideReason? fromName(String? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

enum EgoTrigger { repeatedMaxOverrides, weightUpE1rmDown }

class EgoFlagResult {
  const EgoFlagResult(this.triggers);
  final Set<EgoTrigger> triggers;

  bool get flagged => triggers.isNotEmpty;

  String get message {
    final parts = <String>[
      if (triggers.contains(EgoTrigger.repeatedMaxOverrides))
        '2 of your last 3 sessions had overrides at RPE 9.5+',
      if (triggers.contains(EgoTrigger.weightUpE1rmDown))
        'the weight went up while your estimated 1RM went down',
    ];
    return 'Ego lifting detected: ${parts.join(' and ')}. Progression is frozen for 7 days at −5%.';
  }
}

/// Anti-ego-lifting rules.
class Guardrail {
  const Guardrail();

  static const double overrideTolerance = 0.05;
  static const Duration freezeDuration = Duration(days: 7);

  /// A working set more than 5 % heavier than the suggestion is an override.
  /// With a bodyweight suggestion (0 kg), any added load is an override.
  bool isOverride({required double weight, required double? suggested, required bool isWarmup}) {
    if (isWarmup || suggested == null) return false;
    if (suggested <= 0) return weight > 0;
    return weight > suggested * (1 + overrideTolerance) + 1e-9;
  }

  /// Evaluates the ego flag over the last 3 sessions of an exercise that started after [since]
  /// (the start of the previous freeze, so an expired freeze isn't re-triggered by the same sessions).
  EgoFlagResult evaluate(List<ExerciseSessionLog> history, {DateTime? since, double bodyweight = 0}) {
    final logs = history
        .where((l) => l.hasWorkingSets && (since == null || l.date.isAfter(since)))
        .toList();
    if (logs.length < 2) return const EgoFlagResult({});
    final last3 = logs.sublist(logs.length < 3 ? 0 : logs.length - 3);
    final triggers = <EgoTrigger>{};

    final egoSessions = last3.where((l) => l.hasEgoOverrides).length;
    if (egoSessions >= 2) triggers.add(EgoTrigger.repeatedMaxOverrides);

    // Weight up while e1RM down. A coach-prescribed increase resets reps to the bottom of the
    // range and lowers e1RM by design, so the heavier sessions must contain the lifter's own
    // overrides for this to count as ego lifting (see docs/DECISIONS.md).
    if (last3.length == 3) {
      final first = last3.first, latest = last3.last;
      final selfImposed = last3.skip(1).any((l) => l.hasOverrides);
      if (selfImposed &&
          latest.topWeight > first.topWeight &&
          latest.bestE1rm(bodyweight: bodyweight) < first.bestE1rm(bodyweight: bodyweight)) {
        triggers.add(EgoTrigger.weightUpE1rmDown);
      }
    }
    return EgoFlagResult(triggers);
  }

  DateTime freezeUntil(DateTime start) => start.add(freezeDuration);

  /// % of working sets (with a suggestion) within ±5 % of the suggested weight.
  /// Returns null when there's nothing to measure.
  double? disciplinePct(Iterable<LoggedSet> sets) {
    var total = 0, followed = 0;
    for (final s in sets) {
      if (!s.isWorking || s.suggestedWeight == null) continue;
      total++;
      if (s.followedSuggestion) followed++;
    }
    if (total == 0) return null;
    return followed / total * 100;
  }
}
