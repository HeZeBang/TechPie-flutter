import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewCookie;

import '../models/feature.dart';
import '../services/session/cookie_provider.dart';
import '../services/session/session_node.dart';
import '../services/third_party_auth_service.dart';

/// The campus session a webview — or a desktop window opened from one —
/// authenticates against: the node its feature reads cookies from, plus the
/// pre-flight that brings both the shared store and that node up to date before
/// a page loads.
class CampusSessionHandle {
  const CampusSessionHandle(this.tpAuth, this.node);

  /// The handle for an app feature's own session.
  factory CampusSessionHandle.forFeature(
    ThirdPartyAuthService tpAuth,
    CookieType cookieType,
  ) =>
      CampusSessionHandle(tpAuth, _nodeFor(tpAuth, cookieType));

  final ThirdPartyAuthService tpAuth;

  /// The node this page reads cookies from. Each feature uses a different
  /// derived session: ecourse runs on the IDS/CASTGC session directly, eams
  /// and the egate apps on their own downstream cookies.
  final SessionNode node;

  /// The cookies to inject, as of the last [prepare].
  List<WebViewCookie> get cookies => _webViewCookies(node.cookieProvider);

  /// Brings the shared store and this node up to date before a page loads: the
  /// account-switch wipe first, so nothing the page injects is collateral, then
  /// the node's scheduled renew.
  ///
  /// A campus page writes its cookies into the browser store once and then
  /// drives its own requests, so a node that had gone stale would show up there
  /// as a login screen — the API path cannot rescue it with a 401 retry. Best
  /// effort: a failed pre-flight still opens the page, which falls back to the
  /// campus SSO redirect.
  Future<void> prepare() async {
    await tpAuth.campusWebSession.prepare();
    try {
      await tpAuth.sessionTree.freshCookie(node);
    } catch (error) {
      debugPrint('Campus session pre-flight failed: $error');
    }
  }

  /// [prepare], then the cookies to inject — for a caller that opens a webview
  /// of its own and cannot come back for them.
  Future<List<WebViewCookie>> freshCookies() async {
    await prepare();
    return cookies;
  }
}

/// The session node an app feature authenticates against.
SessionNode _nodeFor(ThirdPartyAuthService tpAuth, CookieType cookieType) =>
    switch (cookieType) {
      CookieType.ecourse => tpAuth.idsNode,
      CookieType.eams => tpAuth.eamsNode,
      CookieType.egateApp => tpAuth.egateAppNode,
    };

/// Rebuilds a session's cookie string into webview cookie objects, one per
/// `name=value` pair, scoped to the provider's campus host.
List<WebViewCookie> _webViewCookies(CookieProvider? provider) {
  if (provider == null || provider.isEmpty) return const <WebViewCookie>[];
  final domain =
      provider.domain.isNotEmpty ? provider.domain : 'ids.shanghaitech.edu.cn';
  final cookies = <WebViewCookie>[];
  for (final part in provider.cookies.split(';')) {
    final separator = part.indexOf('=');
    if (separator <= 0) continue;
    final name = part.substring(0, separator).trim();
    final value = part.substring(separator + 1).trim();
    if (name.isEmpty || value.isEmpty) continue;
    cookies.add(
      WebViewCookie(name: name, value: value, domain: domain, path: '/'),
    );
  }
  return cookies;
}
