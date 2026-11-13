import 'dart:io';

import '../../../services/session/cookie_provider.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';
import '../platform/genai_login_policy.dart';
import '../platform/genai_transport.dart';
import '../platform/genai_transport_factory.dart';
import 'genai_http_failure.dart';

/// Per-exchange cookie jar. CASTGC never leaves IDS; redirect callbacks are
/// intercepted before a token-bearing landing URL is requested.
final class NativeGenAiIdsExchange {
  NativeGenAiIdsExchange({GenAiTransport Function()? createTransport})
    : _createTransport = createTransport ?? createGenAiTransport;

  final GenAiTransport Function() _createTransport;

  Future<GenAiCredential> exchange(CookieProvider provider, GenAiCancellation cancellation) async {
    cancellation.throwIfCancelled();
    GenAiTransport? transport;
    try {
      if (!GenAiLoginPolicy.hasCampusCookie(provider.cookies)) {
        throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
      }
      final cookies = <Cookie>[];
      for (final part in provider.cookies.split(';')) {
        final separator = part.indexOf('=');
        if (separator <= 0) continue;
        cookies.add(
          Cookie(part.substring(0, separator).trim(), part.substring(separator + 1).trim())
            ..path = '/'
            ..secure = true,
        );
      }
      final jar = <String, List<Cookie>>{'ids.shanghaitech.edu.cn': cookies};
      final active = _createTransport();
      transport = active;
      var uri = GenAiLoginPolicy.loginUri;
      for (var hop = 0; hop < 12; hop++) {
        cancellation.throwIfCancelled();
        if (!GenAiLoginPolicy.allowsNavigation(uri) || uri.hasFragment) {
          throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
        }
        final credential = GenAiLoginPolicy.callback(uri);
        if (credential != null) return credential;
        final now = DateTime.now();
        final outgoing = (jar[uri.host] ?? [])
            .where((cookie) {
              final path = cookie.path ?? '/';
              final matches =
                  uri.path == path ||
                  (uri.path.startsWith(path) &&
                      (path.endsWith('/') || uri.path.substring(path.length).startsWith('/')));
              return matches &&
                  (cookie.name != 'CASTGC' || uri.host == 'ids.shanghaitech.edu.cn') &&
                  cookie.maxAge != 0 &&
                  (cookie.expires == null || cookie.expires!.isAfter(now));
            })
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; ');
        final response = await active.send(
          method: 'GET',
          uri: uri,
          cancellation: cancellation,
          headers: {if (outgoing.isNotEmpty) HttpHeaders.cookieHeader: outgoing},
        );
        try {
          if (response.statusCode >= 400) {
            await checkGenAiHttpStatus(
              statusCode: response.statusCode,
              contentType: uri.host == 'genai.shanghaitech.edu.cn'
                  ? response.headers[HttpHeaders.contentTypeHeader]
                  : null,
              bytes: response.bytes,
              cancellation: cancellation,
            );
          }
          final current = jar.putIfAbsent(uri.host, () => []);
          for (final value in _setCookies(response.headers[HttpHeaders.setCookieHeader])) {
            final cookie = Cookie.fromSetCookieValue(value);
            if (cookie.name == 'CASTGC' && uri.host != 'ids.shanghaitech.edu.cn') continue;
            cookie.path ??= '/';
            current.removeWhere((old) => old.name == cookie.name && old.path == cookie.path);
            current.add(cookie);
          }
          final location = response.headers[HttpHeaders.locationHeader];
          if (!const [301, 302, 303, 307, 308].contains(response.statusCode) || location == null) {
            throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
          }
          uri = uri.resolve(location);
        } finally {
          response.close();
        }
      }
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    } on GenAiFailure {
      rethrow;
    } catch (_) {
      cancellation.throwIfCancelled();
      throw const GenAiFailure(GenAiFailureKind.transport);
    } finally {
      transport?.dispose();
    }
  }
}

// HTTP clients expose repeated Set-Cookie fields as a joined value. Split only
// at an unquoted comma followed by a cookie name and '=', never an Expires date.
Iterable<String> _setCookies(String? value) sync* {
  if (value == null || value.isEmpty) return;
  final cookieStart = RegExp(r"^\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+=");
  var start = 0;
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < value.length; i++) {
    final character = value[i];
    if (quoted && character == r'\' && !escaped) {
      escaped = true;
      continue;
    }
    if (character == '"' && !escaped) quoted = !quoted;
    escaped = false;
    if (character == ',' && !quoted && cookieStart.hasMatch(value.substring(i + 1))) {
      yield value.substring(start, i).trim();
      start = i + 1;
    }
  }
  yield value.substring(start).trim();
}
