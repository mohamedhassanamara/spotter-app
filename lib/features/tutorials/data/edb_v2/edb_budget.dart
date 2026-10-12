import 'dart:convert';

/// Monthly request budget for ExerciseDB V2 (RapidAPI plan: 2,000 metadata calls a month; CDN media
/// doesn't count). Pure state: the store persists it as JSON in app settings.
///
/// - Counts every API call per calendar month (local time), resetting on the 1st.
/// - RapidAPI's rate-limit headers, when present, win over the local count:
///   used = x-ratelimit-requests-limit − x-ratelimit-requests-remaining.
/// - Soft warning at [softLimit]; at [hardLimit] the app stops calling until the 1st.
class EdbBudget {
  const EdbBudget({required this.month, this.localCount = 0, this.headerLimit, this.headerRemaining, this.lastCallAt});

  static const int planLimit = 2000;
  static const int softLimit = 1500;
  static const int hardLimit = 1850;

  /// "yyyy-MM" the counters belong to.
  final String month;
  final int localCount;
  final int? headerLimit;
  final int? headerRemaining;
  final DateTime? lastCallAt;

  static String monthOf(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}';

  factory EdbBudget.fresh(DateTime now) => EdbBudget(month: monthOf(now));

  /// The same budget, reset if [now] is in a later month.
  EdbBudget current(DateTime now) => monthOf(now) == month ? this : EdbBudget.fresh(now);

  /// Calls used this month: the server's figure when it sent one, else ours.
  int get used {
    final l = headerLimit, r = headerRemaining;
    if (l != null && r != null) return l - r;
    return localCount;
  }

  bool get fromHeaders => headerLimit != null && headerRemaining != null;

  bool get warn => used >= softLimit;

  bool get stopped => used >= hardLimit;

  /// May the app make one more call at [now]?
  bool allows(DateTime now) => !current(now).stopped;

  /// After a call at [now]; [headers] are the response headers (lower-case keys), if any.
  EdbBudget record(DateTime now, {Map<String, String> headers = const {}}) {
    final base = current(now);
    final limit = int.tryParse(headers['x-ratelimit-requests-limit'] ?? '');
    final remaining = int.tryParse(headers['x-ratelimit-requests-remaining'] ?? '');
    return EdbBudget(
      month: base.month,
      localCount: base.localCount + 1,
      headerLimit: limit ?? base.headerLimit,
      headerRemaining: remaining ?? base.headerRemaining,
      lastCallAt: now,
    );
  }

  /// The first day of next month, when a hard stop lifts.
  DateTime resumesOn() {
    final y = int.parse(month.substring(0, 4)), m = int.parse(month.substring(5));
    return DateTime(y, m + 1);
  }

  String encode() => jsonEncode({
        'month': month,
        'local': localCount,
        if (headerLimit != null) 'hlimit': headerLimit,
        if (headerRemaining != null) 'hremaining': headerRemaining,
        if (lastCallAt != null) 'last': lastCallAt!.toIso8601String(),
      });

  static EdbBudget decode(String? raw, DateTime now) {
    if (raw == null) return EdbBudget.fresh(now);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return EdbBudget(
      month: j['month'] as String,
      localCount: (j['local'] as num).toInt(),
      headerLimit: (j['hlimit'] as num?)?.toInt(),
      headerRemaining: (j['hremaining'] as num?)?.toInt(),
      lastCallAt: j['last'] == null ? null : DateTime.parse(j['last'] as String),
    ).current(now);
  }
}
