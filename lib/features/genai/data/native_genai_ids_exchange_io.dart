import 'dart:io';

import '../../../services/session/cookie_provider.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';
import '../platform/genai_login_policy.dart';
import 'genai_http_failure.dart';

/// Per-exchange cookie jar. CASTGC never leaves IDS; redirect callbacks are
/// intercepted before a token-bearing landing URL is requested.
final class NativeGenAiIdsExchange {
  NativeGenAiIdsExchange({HttpClient Function()? createClient})
      : _createClient = createClient ?? HttpClient.new;

  final HttpClient Function() _createClient;

  Future<GenAiCredential> exchange(
    CookieProvider provider,
    GenAiCancellation cancellation,
  ) async {
    cancellation.throwIfCancelled();
    HttpClient? client;
    void Function()? remove;
    try {
      final cookies = <Cookie>[];
      if (provider.cookies.length > 65536 ||
          provider.cookies.codeUnits.any((c) => c < 32 || c == 127)) {
        throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
      }
      for (final part in provider.cookies.split(';')) {
        final i = part.indexOf('=');
        if (i <= 0) continue;
        cookies.add(
          Cookie(part.substring(0, i).trim(), part.substring(i + 1).trim())
            ..path = '/'
            ..secure = true,
        );
      }
      if (!cookies.any((c) => c.name == 'CASTGC' && c.value.isNotEmpty)) {
        throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
      }
      final jar = <String, List<Cookie>>{'ids.shanghaitech.edu.cn': cookies};
      final activeClient = _createClient();
      client = activeClient;
      activeClient.connectionTimeout = const Duration(seconds: 20);
      remove = cancellation.onCancel(() => activeClient.close(force: true));
      var uri = GenAiLoginPolicy.loginUri;
      for (var hop = 0; hop < 12; hop++) {
        cancellation.throwIfCancelled();
        if (!GenAiLoginPolicy.allowsNavigation(uri) || uri.hasFragment) {
          throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
        }
        final credential = GenAiLoginPolicy.callback(uri);
        if (credential != null) return credential;
        final request = await cancellation.race(activeClient.getUrl(uri));
        request.followRedirects = false;
        final now = DateTime.now();
        request.cookies.addAll(
          (jar[uri.host] ?? []).where((cookie) {
            final path = cookie.path ?? '/';
            final pathMatches = uri.path == path ||
                (uri.path.startsWith(path) &&
                    (path.endsWith('/') || uri.path.substring(path.length).startsWith('/')));
            return pathMatches &&
                (cookie.name != 'CASTGC' || uri.host == 'ids.shanghaitech.edu.cn') &&
                cookie.maxAge != 0 &&
                (cookie.expires == null || cookie.expires!.isAfter(now));
          }),
        );
        final response = await cancellation.race(
          request.close().timeout(const Duration(seconds: 30)),
        );
        var inspectedError = false;
        try {
          if (response.statusCode >= 400) {
            inspectedError = true;
            await checkGenAiHttpStatus(
              statusCode: response.statusCode,
              contentType: uri.host == 'genai.shanghaitech.edu.cn'
                  ? response.headers.value(HttpHeaders.contentTypeHeader)
                  : null,
              bytes: response,
              cancellation: cancellation,
            );
          }
          final current = jar.putIfAbsent(uri.host, () => []);
          for (final cookie in response.cookies) {
            if (cookie.name == 'CASTGC' && uri.host != 'ids.shanghaitech.edu.cn') {
              continue;
            }
            current.removeWhere(
              (c) => c.name == cookie.name && c.path == cookie.path,
            );
            current.add(cookie);
          }
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (!const [301, 302, 303, 307, 308].contains(response.statusCode) || location == null) {
            throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
          }
          uri = uri.resolve(location);
        } finally {
          // Bodies are not needed for a CAS redirect. Cancelling the stream
          // releases the response without retaining login HTML or credentials.
          if (!inspectedError) await response.listen((_) {}).cancel();
        }
      }
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    } on GenAiFailure {
      rethrow;
    } catch (_) {
      cancellation.throwIfCancelled();
      throw const GenAiFailure(GenAiFailureKind.transport);
    } finally {
      remove?.call();
      client?.close(force: true);
    }
  }
}
