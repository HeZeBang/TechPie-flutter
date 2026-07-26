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

  LogEntry({
    required this.timestamp,
    required this.method,
    required this.url,
    this.statusCode,
    this.requestBody,
    this.responseBody,
    this.error,
    this.tag,
  });
}

class DebugLogger extends ChangeNotifier {
  static const int _maxEntries = 500;

  final List<LogEntry> _entries = [];
  bool _enabled = false;

  List<LogEntry> get entries => List.unmodifiable(_entries);
  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  void log({
    required String method,
    required String url,
    int? statusCode,
    String? requestBody,
    String? responseBody,
    String? error,
    String? tag,
  }) {
    if (!_enabled) return;
    if (_entries.length >= _maxEntries) {
      _entries.removeAt(0);
    }
    final entry = LogEntry(
      timestamp: DateTime.now(),
      method: method,
      url: url,
      statusCode: statusCode,
      requestBody: requestBody,
      responseBody: responseBody,
      error: error,
      tag: tag,
    );
    _entries.add(entry);
    notifyListeners();
    if (kDebugMode) {
      debugPrint(
        '[HTTP] ${entry.method} ${entry.url} '
        '${entry.statusCode ?? '—'} ${entry.tag ?? ''}',
      );
    }
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
