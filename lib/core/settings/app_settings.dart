import 'dart:convert';

import '../domain/equipment.dart';
import '../domain/training.dart';
import '../domain/weight_step.dart';

/// Typed view over the `app_settings` key/value table.
class SettingsModel {
  const SettingsModel({
    this.onboarded = false,
    this.streakReminder = true,
    this.increments = Increments.defaults,
    this.exerciseSteps = const {},
    this.exercisePatterns = const {},
    this.compoundRange = RepRange.compound,
    this.isolationRange = RepRange.isolation,
    this.defaultRir = 2,
    this.defaultRestCompound = 150,
    this.defaultRestIsolation = 90,
    this.useFakeHealth = false,
    this.healthPermissionsRequested = false,
    this.restEndsAt,
    this.restTotalSeconds,
  });

  final bool onboarded;
  /// 18:00 reminder on the streak's last-chance day (Settings → Streak).
  final bool streakReminder;
  final Increments increments;

  /// Per-exercise − / + keypad step in kg (long-press on the keypad's − / +). Absent = the equipment default.
  final Map<String, double> exerciseSteps;

  /// Movement pattern (MovementPattern.name) chosen for an exercise, e.g. when a custom exercise is created: decides its estimated rank standard.
  final Map<String, String> exercisePatterns;
  final RepRange compoundRange;
  final RepRange isolationRange;
  final int defaultRir;
  final int defaultRestCompound;
  final int defaultRestIsolation;

  /// Debug builds only: read Health data from the deterministic fake source.
  final bool useFakeHealth;
  final bool healthPermissionsRequested;

  /// Running rest timer (survives app restarts).
  final DateTime? restEndsAt;
  final int? restTotalSeconds;

  static const kOnboarded = 'onboarded';
  static const kStreakReminder = 'streak_reminder';
  static const kIncrements = 'increments';
  static const kExerciseSteps = 'exercise_steps';
  static const kExercisePatterns = 'exercise_patterns';
  static const kCompoundRange = 'compound_range';
  static const kIsolationRange = 'isolation_range';
  static const kDefaultRir = 'default_rir';
  static const kRestCompound = 'rest_compound';
  static const kRestIsolation = 'rest_isolation';
  static const kFakeHealth = 'fake_health';
  static const kHealthRequested = 'health_requested';
  static const kRestEndsAt = 'rest_ends_at';
  static const kRestTotal = 'rest_total';

  factory SettingsModel.fromMap(Map<String, String> m) {
    Increments increments = Increments.defaults;
    final rawInc = m[kIncrements];
    if (rawInc != null) {
      final decoded = (jsonDecode(rawInc) as Map<String, dynamic>);
      final values = {...Increments.defaults.values};
      decoded.forEach((k, v) {
        final kind = EquipmentKind.fromName(k);
        if (kind != null && v is num && v > 0) values[kind] = v.toDouble();
      });
      increments = Increments(values);
    }
    RepRange parseRange(String? raw, RepRange fallback) {
      if (raw == null) return fallback;
      final p = raw.split('-');
      if (p.length != 2) return fallback;
      final a = int.tryParse(p[0]), b = int.tryParse(p[1]);
      if (a == null || b == null || a < 1 || b < a) return fallback;
      return RepRange(a, b);
    }

    final restEnds = m[kRestEndsAt];
    return SettingsModel(
      onboarded: m[kOnboarded] == 'true',
      streakReminder: m[kStreakReminder] != 'false',
      increments: increments,
      exerciseSteps: decodeExerciseSteps(m[kExerciseSteps]),
      exercisePatterns: decodePatterns(m[kExercisePatterns]),
      compoundRange: parseRange(m[kCompoundRange], RepRange.compound),
      isolationRange: parseRange(m[kIsolationRange], RepRange.isolation),
      defaultRir: int.tryParse(m[kDefaultRir] ?? '') ?? 2,
      defaultRestCompound: int.tryParse(m[kRestCompound] ?? '') ?? 150,
      defaultRestIsolation: int.tryParse(m[kRestIsolation] ?? '') ?? 90,
      useFakeHealth: m[kFakeHealth] == 'true',
      healthPermissionsRequested: m[kHealthRequested] == 'true',
      restEndsAt: restEnds == null ? null : DateTime.tryParse(restEnds),
      restTotalSeconds: int.tryParse(m[kRestTotal] ?? ''),
    );
  }

  static Map<String, String> decodePatterns(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      return {for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries) e.key: e.value as String};
    } catch (_) {
      return const {};
    }
  }

  static String encodeIncrements(Increments inc) =>
      jsonEncode({for (final e in inc.values.entries) e.key.name: e.value});

  static String encodeRange(RepRange r) => '${r.min}-${r.max}';
}
