/// Date helpers. All calendar logic uses local time, weeks start on Monday.
library;

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// Monday 00:00 of the week containing [t].
DateTime weekStart(DateTime t) {
  final d = dateOnly(t);
  return DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
}

/// `yyyy-MM-dd` key for a local date.
String dayKey(DateTime t) {
  final d = dateOnly(t);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

DateTime parseDayKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
