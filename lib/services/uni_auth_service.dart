import 'dart:async';
import 'dart:convert';

import 'package:casdoor_flutter_sdk/casdoor_flutter_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../pages/uni_auth_webview_page.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'debug_logger.dart';
import 'http_client.dart';

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

/// Classification of an SSO refresh-token failure so callers can separate a
/// definitively expired/revoked grant from transient network/server hiccups.
enum SsoRefreshErrorKind {
  /// The OAuth server explicitly rejected the refresh token (`invalid_grant`
  /// or `invalid_token`) — the user genuinely needs to sign in again.
  invalidGrant,

  /// Offline/DNS/TLS/timeout/proxy error, 5xx outage, non-JSON response, or
  /// other non-grant failure where the stored refresh token may still work.
  transient,
}

/// Structured error thrown by [UniAuthService.refresh].
class SsoRefreshException implements Exception {
  final SsoRefreshErrorKind kind;
  final String message;
  final int? statusCode;
  final String? oauthError;
  final String? oauthErrorDescription;
  final Object? cause;

  const SsoRefreshException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.oauthError,
    this.oauthErrorDescription,
    this.cause,
  });

  bool get isInvalidGrant => kind == SsoRefreshErrorKind.invalidGrant;

  @override
  String toString() {
    final meta = <String>[
      kind.name,
      if (statusCode != null) 'status=$statusCode',
      if (oauthError != null && oauthError!.isNotEmpty) 'error=$oauthError',
      if (cause != null) 'cause=${cause.runtimeType}',
    ];
    return 'SsoRefreshException(${meta.join(', ')}): $message';
  }
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

  static const Duration _defaultRefreshTimeout = Duration(seconds: 15);

  Casdoor? _casdoor;
  bool _loading = false;

  bool get loading => _loading;

  UniAuthService({
    DebugLogger? logger,
    String proxyUrl = '',
    @visibleForTesting
    Future<http.Response> Function(String refreshToken)? refreshRequest,
    @visibleForTesting Duration refreshTimeout = _defaultRefreshTimeout,
  })  : _logger = logger,
        _proxyUrl = _sanitizeProxy(proxyUrl),
        _refreshRequest = refreshRequest,
        _refreshTimeout = refreshTimeout;

  String _proxyUrl;
  String get proxyUrl => _proxyUrl;
  void setProxyUrl(String value) => _proxyUrl = _sanitizeProxy(value);

  static String _sanitizeProxy(String value) {
    final normalized = normalizeAppProxy(value);
    return isValidAppProxy(normalized) ? normalized : '';
  }

  final DebugLogger? _logger;
  final Future<http.Response> Function(String refreshToken)? _refreshRequest;
  final Duration _refreshTimeout;

  Future<void> deleteAccount(String token, String userId) async {
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final accountResponse = await http.get(
      Uri.parse('$_uniAuthServerUrl/api/get-account'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));
    final accountBody = jsonDecode(accountResponse.body) as Map<String, dynamic>;
    final user = accountBody['data'];
    if (accountResponse.statusCode != 200 || accountBody['status'] != 'ok' ||
        user is! Map || user['id'] != userId || user['owner'] != _uniAuthOrg ||
        user['name'] is! String || (user['name'] as String).isEmpty) {
      throw Exception('无法确认当前账号，请重新登录。');
    }
    if (accountBody['data2']?['enableSoftDeletion'] != false) {
      throw Exception('账号服务未开放永久注销。');
    }
    // Use the user's own token; never send an admin credential or the full profile.
    final response = await http.post(
      Uri.parse('$_uniAuthServerUrl/api/delete-user'),
      headers: headers,
      body: jsonEncode({'owner': user['owner'], 'name': user['name']}),
    ).timeout(const Duration(seconds: 10));
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || result['status'] != 'ok' ||
        result['data'] != 'Affected') {
      throw Exception('账号未注销成功。');
    }
  }

  /// The SDK uses its own HTTP client. Record its HTTP status and whether
  /// it returned a rotated refresh token.
  void _traceTokenResponse(String operation, http.Response response) {
    String summary;
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final parts = <String>[
          'status=${response.statusCode}',
          'rotated=${body['refresh_token'] is String && (body['refresh_token'] as String).isNotEmpty}',
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
      uri: Uri.parse(_uniAuthServerUrl),
      statusCode: response.statusCode,
      tag: 'SSO',
      responseSummary: {'event': line},
    );
  }

  void _traceTokenError(String operation, Object error) {
    final line = 'token $operation: error=${error.runtimeType}';
    if (kDebugMode) debugPrint('[sso] $line');
    _logger?.log(
      method: 'SSO',
      uri: Uri.parse(_uniAuthServerUrl),
      tag: 'SSO',
      error: line,
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
    // Sign-in is a modal step over the whole app, never a page inside a tab.
    final navigator = Navigator.of(context, rootNavigator: true);
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
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        try {
          callbackUrl = await const MethodChannel('techpie/uni_auth')
                  .invokeMethod<String>(
                    'authenticate',
                    <String, String>{
                      'url': casdoor.getSigninUrl().toString(),
                      'proxy': proxyUrl,
                    },
                  ) ??
              '';
        } on PlatformException catch (error) {
          if (error.code == 'CANCELLED') throw CasdoorAuthCancelledException();
          rethrow;
        }
      } else {
        // Windows uses the SDK's desktop WebView window; web keeps its
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

  /// Parse a Casdoor `/api/login/oauth/refresh_token` response into [SsoTokens],
  /// or throw [SsoRefreshException] classifying `invalid_grant`/`invalid_token`
  /// separately from transient server/proxy/format failures.
  static SsoTokens parseRefreshResponse(
    http.Response resp, {
    required String fallbackRefreshToken,
    DateTime? now,
  }) {
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else if (decoded is Map) {
        data = decoded.cast<String, dynamic>();
      }
    } catch (_) {
      // Non-JSON body (e.g. nginx 502/503 HTML or captive portal page).
    }

    if (resp.statusCode == 200 && data != null) {
      final accessToken = data['access_token'] as String?;
      if (accessToken != null && accessToken.isNotEmpty) {
        final rotated = data['refresh_token'] as String?;
        return SsoTokens(
          accessToken: accessToken,
          // Casdoor may rotate the refresh token; keep the new one if present
          // and non-empty, otherwise reuse the one we just redeemed.
          refreshToken:
              (rotated != null && rotated.isNotEmpty) ? rotated : fallbackRefreshToken,
          expiresAt: expiryFromTokenResponse(data, now ?? DateTime.now()),
        );
      }
    }

    final oauthError = data?['error']?.toString().trim();
    final oauthDescription = data?['error_description']?.toString().trim();
    final normalizedError = oauthError?.toLowerCase();
    final isInvalidGrant = resp.statusCode < 500 &&
        (normalizedError == 'invalid_grant' ||
            normalizedError == 'invalid_token');

    final message = (oauthDescription != null && oauthDescription.isNotEmpty)
        ? oauthDescription
        : (oauthError != null && oauthError.isNotEmpty)
            ? oauthError
            : 'Token refresh failed (${resp.statusCode})';

    throw SsoRefreshException(
      kind: isInvalidGrant
          ? SsoRefreshErrorKind.invalidGrant
          : SsoRefreshErrorKind.transient,
      message: message,
      statusCode: resp.statusCode,
      oauthError: oauthError,
      oauthErrorDescription: oauthDescription,
    );
  }

  /// Refresh an existing access token using [refreshToken]. Returns the new
  /// token bundle (the refresh token may be rotated by Casdoor). Throws
  /// [SsoRefreshException] on failure so callers can distinguish an expired or
  /// revoked grant from transient network/server errors.
  Future<SsoTokens> refresh(String refreshToken) async {
    final http.Response resp;
    try {
      final future = _refreshRequest != null
          ? _refreshRequest(refreshToken)
          : _getCasdoor().refreshToken(refreshToken, null);
      resp = await future.timeout(_refreshTimeout);
    } catch (error) {
      _traceTokenError('refresh', error);
      throw SsoRefreshException(
        kind: SsoRefreshErrorKind.transient,
        message: 'Token refresh request failed (${error.runtimeType})',
        cause: error,
      );
    }

    _traceTokenResponse('refresh', resp);
    return parseRefreshResponse(
      resp,
      fallbackRefreshToken: refreshToken,
    );
  }
}
