import 'dart:convert';

import '../domain/equipment.dart';
import '../domain/training.dart';

/// Typed view over the `app_settings` key/value table.
class SettingsModel {
  const SettingsModel({
    this.onboarded = false,
    this.weeklyGoal = 6,
    this.increments = Increments.defaults,
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
  final int weeklyGoal;
  final Increments increments;
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
  static const kWeeklyGoal = 'weekly_goal';
  static const kIncrements = 'increments';
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
      weeklyGoal: int.tryParse(m[kWeeklyGoal] ?? '') ?? 6,
      increments: increments,
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

  static String encodeIncrements(Increments inc) =>
      jsonEncode({for (final e in inc.values.entries) e.key.name: e.value});

  static String encodeRange(RepRange r) => '${r.min}-${r.max}';
}
