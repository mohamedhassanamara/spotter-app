import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ErrorEntry {
  const ErrorEntry({required this.at, required this.source, required this.error, required this.stack, required this.route});

  final DateTime at;

  /// flutter | platform | caught
  final String source;
  final String error;
  final String stack;
  final String? route;

  Map<String, Object?> toJson() =>
      {'at': at.toIso8601String(), 'source': source, 'error': error, 'stack': stack, 'route': route};

  factory ErrorEntry.fromJson(Map<String, dynamic> j) => ErrorEntry(
        at: DateTime.parse(j['at'] as String),
        source: j['source'] as String? ?? 'caught',
        error: j['error'] as String? ?? '',
        stack: j['stack'] as String? ?? '',
        route: j['route'] as String?,
      );

  String format() => '[${at.toIso8601String()}] ($source) route=${route ?? '?'}\n$error\n$stack';
}

/// Persistent in-app error log (Application Support/error_log.jsonl, newest last, capped).
/// Fed by FlutterError.onError, PlatformDispatcher.onError and explicit [recordCaught] calls,
/// so bugs on the phone can be copied out from Settings (long-press the version label).
class ErrorLog {
  ErrorLog._();
  static final ErrorLog instance = ErrorLog._();

  static const int maxEntries = 300;

  /// Current route, kept up to date by the router.
  String? currentRoute;

  final List<ErrorEntry> _entries = [];
  final _changes = StreamController<List<ErrorEntry>>.broadcast();
  File? _file;
  Future<void>? _loading;
  Future<void> _writing = Future.value();

  /// Overridable in tests (no path_provider there).
  @visibleForTesting
  Directory? directoryOverride;

  Stream<List<ErrorEntry>> get changes => _changes.stream;

  Future<void> init() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final dir = directoryOverride ?? await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final f = File('${dir.path}/error_log.jsonl');
      _file = f;
      if (await f.exists()) {
        for (final line in await f.readAsLines()) {
          if (line.trim().isEmpty) continue;
          try {
            _entries.add(ErrorEntry.fromJson(jsonDecode(line) as Map<String, dynamic>));
          } catch (_) {/* skip a corrupt line */}
        }
      }
    } catch (e) {
      debugPrint('ErrorLog init failed: $e');
    }
  }

  Future<List<ErrorEntry>> entries() async {
    await init();
    return List.unmodifiable(_entries);
  }

  void record(Object error, StackTrace? stack, {String source = 'caught'}) {
    final entry = ErrorEntry(
      at: DateTime.now(),
      source: source,
      error: '$error',
      stack: (stack ?? StackTrace.current).toString().split('\n').take(40).join('\n'),
      route: currentRoute,
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) _entries.removeRange(0, _entries.length - maxEntries);
    _changes.add(List.unmodifiable(_entries));
    _writing = _writing.then((_) => _persist()).catchError((Object e) => debugPrint('ErrorLog write failed: $e'));
  }

  /// For catch blocks that recover (show a snackbar) but should still leave a trace.
  void recordCaught(Object error, StackTrace stack) => record(error, stack, source: 'caught');

  Future<void> _persist() async {
    await init();
    final f = _file;
    if (f == null) return;
    await f.writeAsString('${_entries.map((e) => jsonEncode(e.toJson())).join('\n')}\n', flush: true);
  }

  Future<void> clear() async {
    _entries.clear();
    _changes.add(const []);
    _writing = _writing.then((_) => _persist());
    await _writing;
  }

  Future<String> exportText() async {
    final list = await entries();
    if (list.isEmpty) return 'No errors recorded.';
    return list.reversed.map((e) => e.format()).join('\n\n---\n\n');
  }

  /// Waits for pending writes (tests).
  Future<void> flush() => _writing;

  /// Installs the global handlers. Keeps Flutter's default console reporting.
  void installGlobalHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack, source: 'flutter');
      (previous ?? FlutterError.presentError)(details);
    };
    final platformPrevious = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, source: 'platform');
      return platformPrevious?.call(error, stack) ?? true;
    };
  }
}
