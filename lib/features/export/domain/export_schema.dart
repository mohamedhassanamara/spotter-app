/// Export schema helpers (pure Dart). See docs/export_schema.md.
library;

const int exportSchemaVersion = 1;

/// ISO 8601 with the local UTC offset, second precision: `2026-10-12T18:05:00+02:00`.
String isoLocal(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final off = l.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final a = off.abs();
  return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}'
      'T${two(l.hour)}:${two(l.minute)}:${two(l.second)}'
      '$sign${two(a.inHours)}:${two(a.inMinutes % 60)}';
}

String? isoLocalOrNull(DateTime? t) => t == null ? null : isoLocal(t);

/// `yyyyMMdd-HHmm` for file names.
String fileStamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
}

/// RFC 4180 field quoting.
String csvField(Object? v) {
  if (v == null) return '';
  final s = v is double ? _num(v) : v.toString();
  if (s.contains(RegExp(r'[",\r\n]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Builds a CSV document (CRLF line endings) from a header and row maps.
String toCsv(List<String> columns, Iterable<Map<String, Object?>> rows) {
  final b = StringBuffer()..write(columns.map(csvField).join(','))..write('\r\n');
  for (final r in rows) {
    b..write(columns.map((c) => csvField(r[c])).join(','))..write('\r\n');
  }
  return b.toString();
}

const sessionCsvColumns = [
  'id',
  'name',
  'routine_id',
  'started_at',
  'ended_at',
  'duration_s',
  'notes',
  'readiness_score',
  'readiness_band',
  'xp_earned',
  'health_synced',
];

const setCsvColumns = [
  'session_id',
  'session_started_at',
  'session_exercise_id',
  'exercise_id',
  'exercise_name',
  'exercise_position',
  'rep_min',
  'rep_max',
  'target_rir',
  'suggestion_kind',
  'set_id',
  'position',
  'is_warmup',
  'weight_kg',
  'reps',
  'rpe',
  'rir',
  'completed',
  'completed_at',
  'suggested_weight_kg',
  'suggested_reps',
  'is_override',
  'override_reason',
  'e1rm_kg',
  'is_ego_set',
];

const readinessCsvColumns = [
  'date',
  'hrv_ms',
  'resting_hr_bpm',
  'sleep_minutes',
  'active_energy_kcal',
  'readiness_score',
  'readiness_band',
  'calibrating',
  'explanation',
];
