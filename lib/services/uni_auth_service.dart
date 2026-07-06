import 'dart:convert';

import 'package:casdoor_flutter_sdk/casdoor_flutter_sdk.dart';
import 'package:flutter/widgets.dart';

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
  /// Requires a BuildContext for the full-screen presentation.
  Future<String> login(BuildContext context) async {
    _loading = true;
    notifyListeners();
    try {
      final casdoor = _getCasdoor();
      final code = await casdoor.showFullscreen(context);
      if (code.isEmpty) {
        throw Exception('Login cancelled or failed');
      }

      // Exchange authorization code for JWT token.
      final resp = await casdoor.requestOauthAccessToken(code);
      if (resp.statusCode != 200) {
        throw Exception('Token exchange failed (${resp.statusCode})');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception(data['error_description'] ?? 'Token exchange failed');
      }

      return accessToken;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Open the GeekPie Uni-Auth login using a system browser (no BuildContext).
  /// Used by the native iOS liquid glass login sheet.
  Future<String> loginSdkOnly() async {
    _loading = true;
    notifyListeners();
    try {
      final casdoor = _getCasdoor();
      final code = await casdoor.show();
      if (code.isEmpty) {
        throw Exception('Login cancelled or failed');
      }

      final resp = await casdoor.requestOauthAccessToken(code);
      if (resp.statusCode != 200) {
        throw Exception('Token exchange failed (${resp.statusCode})');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception(data['error_description'] ?? 'Token exchange failed');
      }

      return accessToken;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Refresh an existing JWT token.
  Future<String> refreshToken(String refreshTokenValue) async {
    final casdoor = _getCasdoor();
    final resp = await casdoor.refreshToken(refreshTokenValue, null);
    if (resp.statusCode != 200) {
      throw Exception('Token refresh failed (${resp.statusCode})');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception(data['error_description'] ?? 'Token refresh failed');
    }

    return accessToken;
  }
}
