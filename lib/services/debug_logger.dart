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
      requestBody: redactSensitive(requestBody),
      responseBody: redactSensitive(responseBody),
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

  static const _sensitiveKeys = {
    'password',
    'token',
    'tgc',
    'sessionToken',
    'api_token',
    'sid',
    'sid.sig',
    'CASTGC',
    'castgc',
    'cookies',
    'cookie',
    // Cloud-sync: the derived master key and the encrypted blob both must
    // never appear in logs (the blob is ciphertext, but leaking it still
    // gives an attacker an offline target; the key is the crown jewel).
    'techpie_sync',
    'sync_master_key',
  };

  // Best-effort redaction: parse as JSON and walk the tree replacing
  // sensitive values with "***". Falls back to regex on the raw string.
  static String? redactSensitive(String? body) {
    if (body == null || body.isEmpty) return body;
    try {
      final decoded = jsonDecode(body);
      return jsonEncode(_redactNode(decoded));
    } catch (_) {
      var out = body;
      for (final key in _sensitiveKeys) {
        final pattern = RegExp(
          '"${RegExp.escape(key)}"\\s*:\\s*"([^"\\\\]|\\\\.)*"',
        );
        out = out.replaceAll(pattern, '"$key":"***"');
      }
      return out;
    }
  }

  static dynamic _redactNode(dynamic node) {
    if (node is Map) {
      return {
        for (final entry in node.entries)
          entry.key: _sensitiveKeys.contains(entry.key)
              ? (entry.value == null ? null : '***')
              : _redactNode(entry.value),
      };
    }
    if (node is List) return node.map(_redactNode).toList();
    return node;
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
