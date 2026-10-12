import '../../../core/domain/training.dart';

/// Liftoff CSV export (`Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes`).
/// Findings from the owner's export are documented in docs/DECISIONS.md ("Liftoff import").

const double lbPerKg = 2.20462;

double lbToKg(double lb) => lb / lbPerKg;

/// RFC 4180 CSV (quoted fields, doubled quotes, CRLF or LF).
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
  }
  return rows;
}

/// "01 hours 20 minutes 14 seconds" → Duration.
Duration parseLiftoffDuration(String s) {
  int part(String unit) => int.tryParse(RegExp('(\\d+)\\s*$unit').firstMatch(s)?.group(1) ?? '') ?? 0;
  return Duration(hours: part('hour'), minutes: part('minute'), seconds: part('second'));
}

/// "2026-06-12 08:44:09" (local time).
DateTime parseLiftoffDate(String s) => DateTime.parse(s.trim().replaceFirst(' ', 'T'));

/// What the owner's per-exercise notes encode, e.g. "2*6-8/20" = two sets of 6–8, then one of 20,
/// "6-8   D" = 6–8 with a drop set, "10 per leg".
class NoteScheme {
  const NoteScheme({required this.ranges, this.techniqueLetter, this.perSide = false, this.pause = false, this.failure = false});

  /// Target range per set position, in order (expanded from "N*range").
  final List<RepRange> ranges;

  /// Trailing technique letter as written (D, M, H…), uninterpreted.
  final String? techniqueLetter;
  final bool perSide;
  final bool pause;
  final bool failure;

  /// Target for the set at [index]; the last range repeats for extra sets.
  RepRange? rangeFor(int index) => ranges.isEmpty ? null : ranges[index < ranges.length ? index : ranges.length - 1];

  static const empty = NoteScheme(ranges: []);
}

NoteScheme parseNote(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return NoteScheme.empty;
  final lower = s.toLowerCase();
  final pause = lower.contains('pause');
  final failure = lower.contains('failure');
  final perSide = lower.contains('per leg') || lower.contains('per side') || lower.contains('per arm');
  String? letter;
  final m = RegExp(r'[.\s]+([A-Za-z])\s*$').firstMatch(s);
  if (m != null && RegExp(r'\d').hasMatch(s.substring(0, m.start))) {
    letter = m.group(1)!.toUpperCase();
    s = s.substring(0, m.start);
  }
  s = s.replaceAll(RegExp(r'per (leg|side|arm)', caseSensitive: false), '');
  final ranges = <RepRange>[];
  for (final part in s.split('/')) {
    final p = part.trim();
    final mm = RegExp(r'^(?:(\d+)\s*\*\s*)?(\d+)(?:\s*-\s*(\d+))?$').firstMatch(p);
    if (mm == null) continue;
    final times = int.tryParse(mm.group(1) ?? '') ?? 1;
    final lo = int.parse(mm.group(2)!);
    final hi = int.tryParse(mm.group(3) ?? '') ?? lo;
    if (hi < lo || times > 10) continue;
    for (var i = 0; i < times; i++) {
      ranges.add(RepRange(lo, hi));
    }
  }
  return NoteScheme(ranges: ranges, techniqueLetter: letter, perSide: perSide, pause: pause, failure: failure);
}

class LiftoffSet {
  const LiftoffSet({required this.order, required this.weightKg, required this.reps, required this.rpe, required this.note});
  final int order;

  /// Converted from pounds, full precision. Assisted exercises are made negative by the importer.
  final double weightKg;
  final int reps;
  final double? rpe;
  final String note;
}

class LiftoffExercise {
  LiftoffExercise(this.name);
  final String name;
  final List<LiftoffSet> sets = [];

  /// Rep scheme from the first non-empty note.
  NoteScheme get scheme => parseNote(sets.map((s) => s.note).firstWhere((n) => n.trim().isNotEmpty, orElse: () => ''));
}

class LiftoffSession {
  LiftoffSession({required this.key, required this.start, required this.duration});

  /// Stable id: the export's Date string (Workout Name is always empty in the owner's export).
  final String key;
  final DateTime start;
  final Duration duration;
  final List<LiftoffExercise> exercises = [];

  DateTime get end => start.add(duration);
  int get setCount => exercises.fold<int>(0, (a, e) => a + e.sets.length);
}

class SkippedRow {
  const SkippedRow(this.line, this.reason, this.exercise);
  final int line;
  final String reason;
  final String exercise;
}

class LiftoffParse {
  const LiftoffParse({required this.sessions, required this.skipped});
  final List<LiftoffSession> sessions;
  final List<SkippedRow> skipped;

  int get setCount => sessions.fold<int>(0, (a, s) => a + s.setCount);
  Set<String> get exerciseNames => {for (final s in sessions) for (final e in s.exercises) e.name};
}

/// Groups rows into sessions by their exact Date timestamp (keeping file order of exercises and
/// set order within each exercise). Skips rows without an exercise and cardio/timed rows
/// (0 reps with distance or seconds), which have no place in a strength log.
LiftoffParse parseLiftoff(String csvText) {
  final rows = parseCsv(csvText);
  if (rows.isEmpty) throw const FormatException('Empty file');
  final header = [for (final h in rows.first) h.trim().replaceFirst('﻿', '')];
  int col(String name) {
    final i = header.indexOf(name);
    if (i < 0) throw FormatException('Not a Liftoff export: missing "$name" column');
    return i;
  }

  final cDate = col('Date'), cDur = col('Duration'), cEx = col('Exercise Name'), cOrder = col('Set Order');
  final cW = col('Weight'), cReps = col('Reps'), cDist = col('Distance'), cSec = col('Seconds'), cRpe = col('RPE'), cNotes = col('Notes');
  String at(List<String> r, int i) => i < r.length ? r[i].trim() : '';

  final sessions = <String, LiftoffSession>{};
  final skipped = <SkippedRow>[];
  for (var line = 1; line < rows.length; line++) {
    final r = rows[line];
    final name = at(r, cEx);
    final date = at(r, cDate);
    if (name.isEmpty || date.isEmpty) {
      skipped.add(SkippedRow(line + 1, 'no exercise', name));
      continue;
    }
    final reps = int.tryParse(at(r, cReps)) ?? 0;
    final dist = double.tryParse(at(r, cDist)) ?? 0;
    final secs = double.tryParse(at(r, cSec)) ?? 0;
    if (reps <= 0 && (dist > 0 || secs > 0)) {
      skipped.add(SkippedRow(line + 1, 'cardio/timed (distance ${dist}km, ${secs.round()}s)', name));
      continue;
    }
    if (reps <= 0) {
      skipped.add(SkippedRow(line + 1, '0 reps', name));
      continue;
    }
    final session = sessions.putIfAbsent(
      date,
      () => LiftoffSession(key: date, start: parseLiftoffDate(date), duration: parseLiftoffDuration(at(r, cDur))),
    );
    var ex = session.exercises.where((e) => e.name == name).firstOrNull;
    if (ex == null) {
      ex = LiftoffExercise(name);
      session.exercises.add(ex);
    }
    ex.sets.add(LiftoffSet(
      order: int.tryParse(at(r, cOrder)) ?? ex.sets.length,
      weightKg: lbToKg(double.tryParse(at(r, cW)) ?? 0),
      reps: reps,
      rpe: double.tryParse(at(r, cRpe)),
      note: at(r, cNotes),
    ));
  }
  for (final s in sessions.values) {
    for (final e in s.exercises) {
      e.sets.sort((a, b) => a.order.compareTo(b.order));
    }
  }
  final list = sessions.values.toList()..sort((a, b) => a.start.compareTo(b.start));
  return LiftoffParse(sessions: list, skipped: skipped);
}

/// Liftoff names that mean an assisted machine (positive weight = assistance in Liftoff).
bool isLiftoffAssisted(String name) => name.toLowerCase().contains('assisted');
