import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'atrust_routing.dart';
import 'debug_logger.dart';

class LoggingHttpClient {
  final http.Client _inner;
  final DebugLogger _logger;

  /// The default client asks [AtrustRouting] where each request goes, so the
  /// campus tunnel can be armed for campus hosts without every service knowing
  /// about it. Tests pass their own [inner] and are unaffected.
  LoggingHttpClient(this._logger, {http.Client? inner})
      : _inner =
            inner ??
            IOClient(HttpClient()..findProxy = AtrustRouting.forUri);

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

  /// Sends [request] exactly as given, **without** following redirects, so a
  /// handshake that has to read each hop's `Location` (CAS, SSO bounces) can do
  /// so itself. `http.Client`'s own redirect handling is on by default and would
  /// swallow the hop that carries the ticket.
  Future<http.Response> send(http.BaseRequest request, {String? tag}) async {
    _logger.log(method: request.method, url: request.url.toString(), tag: tag);
    try {
      final response = await http.Response.fromStream(
        await _inner.send(request),
      );
      _logger.log(
        method: request.method,
        url: request.url.toString(),
        statusCode: response.statusCode,
        tag: tag,
      );
      return response;
    } catch (e) {
      _logger.log(
        method: request.method,
        url: request.url.toString(),
        error: e.toString(),
        tag: tag,
      );
      rethrow;
    }
  }

  Future<http.Response> head(
    Uri url, {
    Map<String, String>? headers,
    String? tag,
  }) async {
    _logger.log(method: 'HEAD', url: url.toString(), tag: tag);
    try {
      final response = await _inner.head(url, headers: headers);
      _logger.log(
        method: 'HEAD',
        url: url.toString(),
        statusCode: response.statusCode,
        tag: tag,
      );
      return response;
    } catch (e) {
      _logger.log(
        method: 'HEAD',
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
