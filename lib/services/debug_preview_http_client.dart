import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Reuses TechPie's existing password/SMS IDS binding requests in the preview.
/// Every unrelated TechPie request remains local, including background fetches.
final class DebugPreviewHttpClient extends http.BaseClient {
  DebugPreviewHttpClient({required String proxyOrigin, http.Client? inner})
      : _proxy = Uri.parse(proxyOrigin),
        _inner = inner ?? http.Client() {
    if (!kDebugMode) throw UnsupportedError('Preview is debug-only');
    if (_proxy.scheme != 'http' ||
        !const ['127.0.0.1', 'localhost', '::1'].contains(_proxy.host) ||
        _proxy.userInfo.isNotEmpty ||
        (_proxy.path.isNotEmpty && _proxy.path != '/') ||
        _proxy.hasQuery ||
        _proxy.hasFragment) {
      throw ArgumentError('Preview requires a loopback proxy');
    }
  }
  final Uri _proxy;
  final http.Client _inner;
  static const _authPaths = {
    '/api/auth/third-party/egate',
    '/api/auth/mobile/send-sms',
    '/api/auth/renew',
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final url = request.url;
    if (request is! http.Request ||
        request.method != 'POST' ||
        url.scheme != 'https' ||
        url.host != 'techpie.geekpie.club' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        !_authPaths.contains(url.path)) {
      return Future.value(
        http.StreamedResponse(
          Stream.value(
            '{"message":"Local preview: campus services are unavailable"}'
                .codeUnits,
          ),
          503,
          headers: {'content-type': 'application/json'},
        ),
      );
    }
    final forwarded = http.Request('POST', _proxy.resolve(url.path))
      ..headers['Content-Type'] = 'application/json'
      ..bodyBytes = request.bodyBytes;
    return _inner.send(forwarded);
  }

  @override
  void close() => _inner.close();
}
