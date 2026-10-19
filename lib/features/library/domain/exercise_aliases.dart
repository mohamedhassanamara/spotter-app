/// Other names an exercise goes by, so the library finds it under any of them: the name in my routines and sessions (e.g. "High-to-Low Cable Fly"
/// for the library's Cable Crossover), the program's own name and its substitutions ("Cable Flye"), and the Liftoff names that map onto it.
Map<String, Set<String>> buildAliases({
  Iterable<({String exerciseId, String? displayName})> usedNames = const [],
  Map<String, dynamic>? myRoutines,
  Map<String, dynamic>? canonicalProgram,
  Map<String, dynamic>? liftoffMap,
}) {
  final out = <String, Set<String>>{};
  void add(String? id, Object? name) {
    if (id == null || name is! String || name.trim().isEmpty) return;
    (out[id] ??= {}).add(name.trim());
  }

  for (final u in usedNames) {
    add(u.exerciseId, u.displayName);
  }

  // My routines: the name I use and the program's name; each program slot also remembers which exercise fills it.
  final byslot = <String, String>{};
  for (final r in (myRoutines?['routines'] as List<dynamic>? ?? const [])) {
    for (final e in ((r as Map<String, dynamic>)['exercises'] as List<dynamic>? ?? const [])) {
      final m = e as Map<String, dynamic>;
      final id = m['exercise_id'] as String?;
      add(id, m['name']);
      add(id, m['program_exercise']);
      for (final s in (m['program_slots'] as List<dynamic>? ?? const [])) {
        if (id != null) byslot[s as String] = id;
      }
    }
  }
  // The program's slots: its exercise name and the two substitutions it lists for it.
  for (final d in (canonicalProgram?['days'] as List<dynamic>? ?? const [])) {
    for (final s in ((d as Map<String, dynamic>)['slots'] as List<dynamic>? ?? const [])) {
      final slot = s as Map<String, dynamic>;
      final id = byslot[slot['slot_id']];
      add(id, slot['exercise']);
      for (final sub in (slot['substitutions'] as List<dynamic>? ?? const [])) {
        add(id, sub is Map ? sub['name'] ?? sub['exercise'] : sub);
      }
    }
  }
  // Liftoff names: a library id, {"id": …}, or {"by_weight": [{"id": …}, …]}.
  for (final e in ((liftoffMap?['map'] as Map<String, dynamic>?) ?? const {}).entries) {
    final v = e.value;
    if (v is String) {
      add(v, e.key);
    } else if (v is Map<String, dynamic>) {
      add(v['id'] as String?, e.key);
      for (final b in (v['by_weight'] as List<dynamic>? ?? const [])) {
        if (b is Map) add(b['id'] as String?, e.key);
      }
    }
  }
  return out;
}

/// "High-to-Low Cable Fly", "high to low cable fly" and "HighToLow" all become comparable text: lower case, punctuation as spaces, plurals stemmed.
List<String> searchTokens(String text, {bool stem = true}) {
  final out = <String>[];
  for (final raw in text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').split(' ')) {
    if (raw.isEmpty) continue;
    out.add(stem ? _stem(raw) : raw);
  }
  return out;
}

String _stem(String w) {
  if (w.length <= 3) return w;
  if (w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.endsWith('yes')) return w.substring(0, w.length - 2); // flyes → fly
  if (RegExp(r'(ches|shes|sses|xes)$').hasMatch(w)) return w.substring(0, w.length - 2);
  if (w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
  return w;
}

/// Whether the search [query] finds [name]: spaces, hyphens and plurals are ignored, and a word typed half-way ("ons") still matches.
bool searchMatches(String name, String query) {
  bool tryWith(bool stem) {
    final q = searchTokens(query, stem: stem), t = searchTokens(name, stem: stem);
    if (q.isEmpty) return true;
    final spaced = t.join(' '), compact = t.join();
    return q.every(spaced.contains) || compact.contains(q.join());
  }

  return tryWith(false) || tryWith(true);
}
