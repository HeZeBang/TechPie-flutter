import 'package:flutter/foundation.dart';

/// A read-only snapshot of cookies + identity a downstream consumer (campus
/// service, webview feature) injects into its requests.
///
/// Implementations: [CpdailyCookieProvider] (CASTGC-bearing CpDaily session),
/// [IdsCookieProvider] (IDS SSO cookies minted from the CpDaily session), and
/// a no-op empty view for leaf nodes that expose no cookies (Gradescope/Hydro
/// work via bearer tokens server-side, not browser cookies).
@immutable
class CookieProvider {
  final String cookies;
  final String studentId;
  final String domain;

  const CookieProvider({
    required this.cookies,
    this.studentId = '',
    this.domain = '',
  });

  /// Empty provider — callers treat [isEmpty] as "session unavailable".
  static const CookieProvider empty = CookieProvider(cookies: '');

  bool get isEmpty => cookies.isEmpty;
}
