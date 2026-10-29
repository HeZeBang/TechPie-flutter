import 'dart:convert';

import 'package:casdoor_flutter_sdk/casdoor_flutter_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../pages/uni_auth_webview_page.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'debug_logger.dart';

// ---------------------------------------------------------------------------
// GeekPie Uni-Auth configuration (powered by Casdoor)
// ---------------------------------------------------------------------------

const String _uniAuthServerUrl = 'https://auth.geekpie.club';
const String _uniAuthOrg = 'geekpie';
const String _uniAuthAppName = 'techpie';
const String _uniAuthClientId = '833e27462c104f1f3406';
const String _uniAuthRedirectUri = 'techpie://auth-callback';
const String _uniAuthCallbackScheme = 'techpie';

// ---------------------------------------------------------------------------
// SSO token bundle
// ---------------------------------------------------------------------------

/// Result of exchanging an OAuth `code` with Casdoor: the access token used to
/// authenticate against the TechPie backend (`/auth/geekpie`) plus the refresh
/// token + expiry needed to renew it later without re-prompting the user.
class SsoTokens {
  final String accessToken;
  final String? refreshToken;
  final String? expiresAt;

  const SsoTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  bool get isEmpty => accessToken.isEmpty;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class UniAuthService extends ChangeNotifier {
  /// Absolute expiry for the access token in a token endpoint response.
  ///
  /// The field is `expires_in` — seconds from now. `expires_at` is a field of
  /// Casdoor's token *model*, which an OAuth response does not contain: parsing
  /// it left every stored expiry null, which is why nothing could tell how much
  /// of a token was left.
  static String? expiryFromTokenResponse(
    Map<String, dynamic> data,
    DateTime now,
  ) {
    final seconds = int.tryParse('${data['expires_in']}');
    if (seconds != null && seconds > 0) {
      return now.add(Duration(seconds: seconds)).toUtc().toIso8601String();
    }
    return data['expires_at'] as String?;
  }

  Casdoor? _casdoor;
  bool _loading = false;

  bool get loading => _loading;

  UniAuthService({DebugLogger? logger}) : _logger = logger;

  final DebugLogger? _logger;

  /// Debug trace of what the SSO token endpoint answered.
  ///
  /// The SDK brings its own HTTP client, so unlike every other call this one is
  /// not in the app's request log — a refresh that keeps failing was therefore
  /// completely invisible, and the only way to tell "the token was refused" from
  /// "the call never landed" is to record it here. Field *names* and the status
  /// are safe; token values are never logged.
  void _traceTokenResponse(String operation, http.Response response) {
    String summary;
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final keys = body.keys.map((k) => k.toString()).toList()..sort();
        final parts = <String>[
          'status=${response.statusCode}',
          'keys=[${keys.join(',')}]',
          if (body['error'] != null) 'error=${body['error']}',
          if (body['error_description'] != null)
            'description=${body['error_description']}',
          if (body['expires_in'] != null) 'expires_in=${body['expires_in']}',
          'rotated=${body['refresh_token'] != null}',
        ];
        summary = parts.join(' ');
      } else {
        summary = 'status=${response.statusCode} (non-object body)';
      }
    } catch (_) {
      summary = 'status=${response.statusCode} (body not JSON)';
    }
    final line = 'token $operation: $summary';
    if (kDebugMode) debugPrint('[sso] $line');
    _logger?.log(
      method: 'SSO',
      url: _uniAuthServerUrl,
      tag: 'SSO',
      responseBody: DebugLogger.redactSensitive(line),
    );
  }

  /// Lazily initialize the Casdoor SDK instance.
  Casdoor _getCasdoor() {
    if (_casdoor != null) return _casdoor!;
    _casdoor = Casdoor(
      config: AuthConfig(
        clientId: _uniAuthClientId,
        serverUrl: _uniAuthServerUrl,
        organizationName: _uniAuthOrg,
        appName: _uniAuthAppName,
        redirectUri: _uniAuthRedirectUri,
        callbackUrlScheme: _uniAuthCallbackScheme,
      ),
    );
    return _casdoor!;
  }

  /// Open the GeekPie Uni-Auth login page in an in-app WebView.
  /// Requires a BuildContext for the full-screen presentation. Returns the
  /// full token bundle (access + refresh + expiry).
  Future<SsoTokens> login(BuildContext context) async {
    final navigator = Navigator.of(context);
    _loading = true;
    notifyListeners();
    try {
      final casdoor = _getCasdoor();
      final String callbackUrl;
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform.name == 'ohos')) {
        final result = await navigator.push<String>(
          adaptivePageRoute<String>(
            builder: (_) => UniAuthWebViewPage(
              authorizeUrl: casdoor.getSigninUrl().toString(),
              callbackUri: Uri.parse(_uniAuthRedirectUri),
            ),
          ),
        );
        if (result == null || result.isEmpty) throw CasdoorAuthCancelledException();
        callbackUrl = result;
      } else {
        // Windows/Linux use the SDK's desktop WebView window; web keeps its
        // browser OAuth flow. Neither needs an intermediate Flutter page.
        callbackUrl = await casdoor.showFullscreen(context);
      }
      final code = _extractCode(callbackUrl);
      if (code.isEmpty) {
        throw Exception('Login cancelled or failed');
      }
      return await _exchangeCode(casdoor, code);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Exchange an authorization code for the SSO token bundle.
  Future<SsoTokens> _exchangeCode(Casdoor casdoor, String code) async {
    final resp = await casdoor.requestOauthAccessToken(code);
    _traceTokenResponse('exchange', resp);
    if (resp.statusCode != 200) {
      throw Exception('Token exchange failed (${resp.statusCode})');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception(data['error_description'] ?? 'Token exchange failed');
    }

    return SsoTokens(
      accessToken: accessToken,
      refreshToken: data['refresh_token'] as String?,
      expiresAt: expiryFromTokenResponse(data, DateTime.now()),
    );
  }

  /// Pull the `code` query parameter out of the callback URL the SDK returns.
  /// casdoor.showFullscreen / casdoor.show yield the full redirect URL
  /// (e.g. `techpie://auth-callback?code=xxx&state=yyy`), not just the code.
  String _extractCode(String callbackUrl) {
    if (callbackUrl.isEmpty) return '';
    final uri = Uri.tryParse(callbackUrl);
    if (uri == null) return '';
    return uri.queryParameters['code'] ?? '';
  }

  /// Refresh an existing access token using [refreshToken]. Returns the new
  /// token bundle (the refresh token may be rotated by Casdoor). Throws on
  /// failure so the caller can fall back to prompting for re-login.
  Future<SsoTokens> refresh(String refreshToken) async {
    final casdoor = _getCasdoor();
    final resp = await casdoor.refreshToken(refreshToken, null);
    _traceTokenResponse('refresh', resp);
    if (resp.statusCode != 200) {
      throw Exception('Token refresh failed (${resp.statusCode})');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception(data['error_description'] ?? 'Token refresh failed');
    }

    return SsoTokens(
      accessToken: accessToken,
      // Casdoor may rotate the refresh token; keep the new one if present,
      // otherwise reuse the one we just redeemed.
      refreshToken: (data['refresh_token'] as String?) ?? refreshToken,
      expiresAt: expiryFromTokenResponse(data, DateTime.now()),
    );
  }
}
