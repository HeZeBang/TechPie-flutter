import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'atrust_routing.dart';
import 'debug_logger.dart';

class LoggingHttpClient {
  final http.Client _inner;
  final DebugLogger _logger;

  /// The aTrust controller, and the address to reach it at when its name does
  /// not resolve.
  ///
  /// `vpn.shanghaitech.edu.cn` is split-horizon: it resolves on the campus
  /// network path and nowhere else — measured from a phone off that path, the
  /// carrier's resolver and Cloudflare's DoT both answered "unknown host" while
  /// every other name worked. Its address is stable (59.78.171.240, measured),
  /// so a lookup that fails falls back to it.
  ///
  /// Only the *socket* moves. The TLS handshake still runs against the name in
  /// the URL, so the SNI and the certificate check are the controller's own:
  /// an address answering for something else cannot be reached quietly.
  static const controllerHost = 'vpn.shanghaitech.edu.cn';
  static const controllerAddress = '59.78.171.240';

  /// Where the connection for [url] is made: by name, by address when the name
  /// goes unanswered, and with TLS either way.
  ///
  /// Three things this has to get exactly right, each of them learned from a
  /// breakage:
  ///
  ///  * the lookup is done here, because [Socket.startConnect] hands back a task
  ///    whose resolution failure surfaces after this function has returned —
  ///    too late to fall back from;
  ///  * the TLS handshake is also this function's job: with a connection factory
  ///    set, `dart:io` uses its socket as-is and never layers TLS on top (see
  ///    `_http/http_impl.dart`), so returning a bare socket sent *plaintext* to
  ///    port 443 and the gateway answered 400;
  ///  * the handshake runs against the *name in the URL* even when the socket
  ///    went to the address, so the fallback cannot quietly reach something whose
  ///    certificate is not the controller's.
  static Future<ConnectionTask<Socket>> connectByNameOrAddress(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    var host = url.host;
    try {
      await InternetAddress.lookup(host);
    } on SocketException {
      if (host != controllerHost) rethrow;
      host = controllerAddress;
    }
    final task = await Socket.startConnect(host, url.port);
    if (!url.isScheme('https')) return task;
    return ConnectionTask.fromSocket(
      task.socket.then((socket) => SecureSocket.secure(socket, host: url.host)),
      task.cancel,
    );
  }

  /// The default client asks [AtrustRouting] where each request goes, so the
  /// campus tunnel can be armed for campus hosts without every service knowing
  /// about it, and [connectByNameOrAddress] where the socket goes. Tests pass
  /// their own [inner] and are unaffected.
  LoggingHttpClient(this._logger, {http.Client? inner})
      : _inner =
            inner ??
            IOClient(
              HttpClient()
                ..findProxy = AtrustRouting.forUri
                ..connectionFactory = connectByNameOrAddress,
            );

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
