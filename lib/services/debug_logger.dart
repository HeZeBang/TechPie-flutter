import 'dart:convert';

import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime timestamp;
  final String method;
  final String url;
  final int? statusCode;
  final String? requestBody;
  final String? responseBody;
  final String? error;
  final String? tag;

  /// How long the request took on the wire, and how much of the wait happened
  /// before it was sent (session preparation, identity checks). The second is
  /// what separates our own overhead from the server's.
  final int? durationMicros;
  final int? prepMicros;

  LogEntry({
    required this.timestamp,
    required this.method,
    required this.url,
    this.statusCode,
    this.requestBody,
    this.responseBody,
    this.error,
    this.tag,
    this.durationMicros,
    this.prepMicros,
  });
}

class DebugLogger extends ChangeNotifier {
  static const int _maxEntries = 500;

  final List<LogEntry> _entries = [];
  bool _enabled = false;

  List<LogEntry> get entries => List.unmodifiable(_entries);
  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value && !kReleaseMode;
    notifyListeners();
  }

  /// Summaries contain locally selected diagnostic fields. Callers keep payloads,
  /// exception messages and headers on the transport side of this boundary.
  void log({
    required String method,
    Uri? uri,
    String? operation,
    int? statusCode,
    Map<String, Object?>? requestSummary,
    Map<String, Object?>? responseSummary,
    String? error,
    String? tag,
    int? durationMicros,
    int? prepMicros,
  }) {
    assert((uri == null) != (operation == null));
    if (!_enabled) return;
    if (_entries.length >= _maxEntries) {
      _entries.removeAt(0);
    }
    final entry = LogEntry(
      timestamp: DateTime.now(),
      method: method,
      url: operation ?? _origin(uri!),
      statusCode: statusCode,
      requestBody: requestSummary == null ? null : jsonEncode(requestSummary),
      responseBody: responseSummary == null ? null : jsonEncode(responseSummary),
      error: error,
      tag: tag,
      durationMicros: durationMicros,
      prepMicros: prepMicros,
    );
    _entries.add(entry);
    notifyListeners();
    if (kDebugMode) {
      final took = entry.durationMicros == null
          ? ''
          : ' ${(entry.durationMicros! / 1000).round()}ms'
              '${entry.prepMicros == null ? '' : ' (prep ${(entry.prepMicros! / 1000).round()}ms)'}';
      debugPrint(
        '[HTTP] ${entry.method} ${entry.url} '
        '${entry.statusCode ?? '—'}$took ${entry.tag ?? ''}',
      );
    }
  }

  static String _origin(Uri uri) =>
      uri.host.isNotEmpty && (uri.isScheme('https') || uri.isScheme('http')) ? uri.origin : '—';

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
