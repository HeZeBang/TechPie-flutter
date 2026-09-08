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
    final timer = Stopwatch()..start();
    _logger.log(method: 'GET', url: url.origin, tag: tag);
    try {
      final response = await _inner
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));
      _logger.log(
        method: 'GET',
        url: url.origin,
        statusCode: response.statusCode,
        elapsedMs: timer.elapsedMilliseconds,
        tag: tag,
      );
      return response;
    } catch (e) {
      _logger.log(
        method: 'GET',
        url: url.origin,
        error: e.runtimeType.toString(),
        elapsedMs: timer.elapsedMilliseconds,
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
    final timer = Stopwatch()..start();
    final bodyStr =
        body is String ? body : (body != null ? jsonEncode(body) : null);
    _logger.log(
      method: 'POST',
      url: url.origin,
      tag: tag,
    );
    try {
      final response = await _inner
          .post(
            url,
            headers: headers,
            body: bodyStr,
            encoding: encoding,
          )
          .timeout(const Duration(seconds: 30));
      _logger.log(
        method: 'POST',
        url: url.origin,
        statusCode: response.statusCode,
        elapsedMs: timer.elapsedMilliseconds,
        tag: tag,
      );
      return response;
    } catch (e) {
      _logger.log(
        method: 'POST',
        url: url.origin,
        error: e.runtimeType.toString(),
        elapsedMs: timer.elapsedMilliseconds,
        tag: tag,
      );
      rethrow;
    }
  }

  void close() => _inner.close();
}
