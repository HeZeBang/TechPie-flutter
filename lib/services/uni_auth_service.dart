import 'dart:convert';

import 'package:casdoor_flutter_sdk/casdoor_flutter_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../pages/macos_casdoor_auth_page.dart';
import '../pages/ohos_casdoor_auth_page.dart';

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
  Casdoor? _casdoor;
  bool _loading = false;

  bool get loading => _loading;

  UniAuthService();

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
      if (defaultTargetPlatform.name == 'ohos') {
        callbackUrl = await _showOhosLogin(navigator, casdoor);
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        callbackUrl = await _showMacosLogin(navigator, casdoor);
      } else {
        callbackUrl = await casdoor.showFullscreen(context);
      }
      final code = extractUniAuthCallbackCode(callbackUrl);
      if (code.isEmpty) {
        throw Exception('Login cancelled or failed');
      }
      return _exchangeCode(casdoor, code);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Open the GeekPie Uni-Auth login using a system browser (no BuildContext).
  /// Used by the native iOS liquid glass login sheet.
  Future<SsoTokens> loginSdkOnly() async {
    _loading = true;
    notifyListeners();
    try {
      final casdoor = _getCasdoor();
      final callbackUrl = await casdoor.show();
      final code = extractUniAuthCallbackCode(callbackUrl);
      if (code.isEmpty) {
        throw Exception('Login cancelled or failed');
      }
      return _exchangeCode(casdoor, code);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String> _showOhosLogin(
    NavigatorState navigator,
    Casdoor casdoor,
  ) async {
    final callbackUrl = await navigator.push<String>(
      MaterialPageRoute<String>(
        builder: (_) => OhosCasdoorAuthPage(
          authorizeUrl: casdoor.getSigninUrl().toString(),
          callbackScheme: _uniAuthCallbackScheme,
        ),
      ),
    );
    if (callbackUrl == null || callbackUrl.isEmpty) {
      throw CasdoorAuthCancelledException();
    }
    return callbackUrl;
  }

  Future<String> _showMacosLogin(
    NavigatorState navigator,
    Casdoor casdoor,
  ) async {
    final callbackUrl = await navigator.push<String>(
      MaterialPageRoute<String>(
        builder: (_) => MacosCasdoorAuthPage(
          authorizeUrl: casdoor.getSigninUrl().toString(),
          callbackScheme: _uniAuthCallbackScheme,
        ),
      ),
    );
    if (callbackUrl == null || callbackUrl.isEmpty) {
      throw CasdoorAuthCancelledException();
    }
    return callbackUrl;
  }

  /// Exchange an authorization code for the SSO token bundle.
  Future<SsoTokens> _exchangeCode(Casdoor casdoor, String code) async {
    final resp = await casdoor.requestOauthAccessToken(code);
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
      expiresAt: data['expires_at'] as String?,
    );
  }

  /// Refresh an existing access token using [refreshToken]. Returns the new
  /// token bundle (the refresh token may be rotated by Casdoor). Throws on
  /// failure so the caller can fall back to prompting for re-login.
  Future<SsoTokens> refresh(String refreshToken) async {
    final casdoor = _getCasdoor();
    final resp = await casdoor.refreshToken(refreshToken, null);
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
      expiresAt: data['expires_at'] as String?,
    );
  }
}

/// Pull the authorization code out of the full callback URL returned by the
/// Casdoor SDK. Kept as a small pure function so the URL contract stays covered
/// without opening a real login WebView in tests.
@visibleForTesting
String extractUniAuthCallbackCode(String callbackUrl) {
  if (callbackUrl.isEmpty) return '';
  final uri = Uri.tryParse(callbackUrl);
  if (uri == null) return '';
  return uri.queryParameters['code'] ?? '';
}
