import 'dart:convert';

import 'package:http/http.dart' as http;

import 'debug_logger.dart';

class LoggingHttpClient {
  final http.Client _inner;
  final DebugLogger _logger;

  LoggingHttpClient(this._logger, {http.Client? inner})
      : _inner = inner ?? http.Client();

  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    String? tag,
  }) async {
    _logger.log(method: 'GET', url: url.toString(), tag: tag);
    try {
      final response = await _inner.get(url, headers: headers);
      _logger.log(
        method: 'GET',
        url: url.toString(),
        statusCode: response.statusCode,
        responseBody: _truncate(response.body),
        tag: tag,
      );
      return response;
    } catch (e) {
      _logger.log(
        method: 'GET',
        url: url.toString(),
        error: e.toString(),
        tag: tag,
      );
      rethrow;
    }
  }

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    String? tag,
  }) async {
    final bodyStr =
        body is String ? body : (body != null ? jsonEncode(body) : null);
    _logger.log(
      method: 'POST',
      url: url.toString(),
      requestBody: bodyStr,
      tag: tag,
    );
    try {
      final response = await _inner.post(
        url,
        headers: headers,
        body: bodyStr,
        encoding: encoding,
      );
      _logger.log(
        method: 'POST',
        url: url.toString(),
        statusCode: response.statusCode,
        responseBody: _truncate(response.body),
        tag: tag,
      );
      return response;
    } catch (e) {
      _logger.log(
        method: 'POST',
        url: url.toString(),
        error: e.toString(),
        tag: tag,
      );
      rethrow;
    }
  }

  String _truncate(String s, [int maxLen = 2000]) =>
      s.length > maxLen ? '${s.substring(0, maxLen)}...' : s;

  void close() => _inner.close();
}
