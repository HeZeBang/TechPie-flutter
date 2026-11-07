import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/account_deletion_request.dart';
import '../models/user_session.dart';
import 'api_base_url.dart';
import 'debug_logger.dart';
import 'http_client.dart';
import 'storage_service.dart';
import 'uni_auth_service.dart';

/// AuthService owns ONLY the primary account: the GeekPie Uni-Auth (Casdoor)
/// SSO identity session. It knows nothing about CASTGC, CpDaily, or any
/// campus-system credential — those live in [ThirdPartyAuthService] (the eGate
/// binding) and are the single source of truth for every CASTGC-dependent
/// feature. Keeping that boundary means an SSO-only user is correctly "logged
/// in" without implying they can reach eGate-gated services.
class AuthService extends ChangeNotifier {
  final StorageService _storage;
  final LoggingHttpClient _http;
  final UniAuthService _uniAuth;

  UserSession? _session;
  bool _loading = false;

  String get _baseUrl => apiBaseUrl(_storage);

  UserSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get loading => _loading;

  // Optional callback fired after primary-account logout so dependent
  // services (e.g. third-party bindings) can clear themselves. Injected
  // post-construction from main.dart to avoid circular construction.
  Future<void> Function()? onLogout;

  /// Fired after a successful SSO login (post-save). SyncService uses it to
  /// pull cloud bindings onto a freshly-logged-in device. Injected from
  /// main.dart to avoid a circular construction dependency.
  Future<void> Function()? onLogin;

  AuthService(this._storage, this._http, this._uniAuth, {DebugLogger? logger}) : _logger = logger;

  final DebugLogger? _logger;

  // -- Initialization & token renewal --

  /// Load the persisted session from secure storage. Pure local I/O —
  /// safe to await on the boot critical path. Network token renewal is
  /// the caller's responsibility (kick it off after `runApp`).
  Future<void> loadSession() async {
    _session = await _storage.loadSession();
    notifyListeners();
  }

  /// Backwards-compatible alias. Network renew is no longer awaited here;
  /// use [tryRenewSession] explicitly if you need it.
  Future<void> initialize() => loadSession();

  /// How close to expiry the access token has to be before a refresh token is
  /// spent on renewing it. Casdoor rotates refresh tokens on use and the access
  /// token lives for days here, so renewing on every launch would churn
  /// credentials for nothing.
  static const renewWindow = Duration(hours: 12);

  /// Whether the stored access token is close enough to expiry to be worth
  /// renewing. An unknown or unreadable expiry renews: not knowing is a reason
  /// to check, not to wait.
  static bool needsRenewal(String? expiresAt, DateTime now, Duration window) {
    final parsed = DateTime.tryParse(expiresAt ?? '');
    if (parsed == null) return true;
    return parsed.isBefore(now.add(window));
  }

  Future<bool>? _renewal;

  /// Renew the SSO access token via Casdoor's refresh-token grant, unless it
  /// still has [renewWindow] left and [force] is not set. On success the rotated
  /// tokens are persisted into the session. Returns false (no throw) when there
  /// is no session, no refresh token, or the refresh fails — the caller decides
  /// whether to prompt for re-login. Skipping a renewal that is not needed
  /// reports true: the session is usable either way.
  ///
  /// Single-flight: Casdoor rotates the refresh token, so two concurrent
  /// renewals would consume each other's credential and one would be refused —
  /// which looks exactly like a dead session.
  Future<bool> tryRenewSession({bool force = false}) {
    final active = _renewal;
    if (active != null) return active;
    if (!force &&
        !needsRenewal(
          _session?.geekpieExpiresAt,
          DateTime.now(),
          renewWindow,
        )) {
      final left = _timeLeft();
      final line = 'token refresh: skipped, $left left';
      if (kDebugMode) debugPrint('[sso] $line');
      _logger?.log(
        method: 'SSO',
        url: 'auth.geekpie.club',
        tag: 'SSO',
        responseBody: DebugLogger.redactSensitive(line),
      );
      return Future.value(true);
    }
    late final Future<bool> operation;
    operation = _performRenewal().whenComplete(() {
      if (identical(_renewal, operation)) _renewal = null;
    });
    _renewal = operation;
    return operation;
  }

  /// How much of the access token is left, for the trace line.
  String _timeLeft() {
    final expiry = DateTime.tryParse(_session?.geekpieExpiresAt ?? '');
    if (expiry == null) return 'unknown';
    final left = expiry.difference(DateTime.now());
    if (left.isNegative) return 'expired';
    final hours = left.inHours;
    return hours >= 24 ? '${hours ~/ 24}d ${hours % 24}h' : '${hours}h';
  }

  Future<bool> _performRenewal() async {
    final session = _session;
    if (session == null) return false;
    final refreshToken = session.geekpieRefreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final tokens = await _uniAuth.refresh(refreshToken);
      _session = session.copyWith(
        geekpieToken: tokens.accessToken,
        geekpieExpiresAt: tokens.expiresAt ?? session.geekpieExpiresAt,
        geekpieRefreshToken: tokens.refreshToken ?? refreshToken,
      );
      await _storage.saveSession(_session!);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // -- GeekPie Uni-Auth Login --

  Future<UserSession> geekpieLogin(SsoTokens tokens) async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/geekpie'),
        headers: _jsonHeaders(),
        body: jsonEncode({'token': tokens.accessToken}),
        tag: 'geekpieLogin',
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error'] as String? ?? 'Login failed');
      }

      _session = UserSession(
        userId: data['userId'] as String? ?? '',
        userName: data['userName'] as String? ?? '',
        schoolName: '上海科技大学',
        createdAt: DateTime.now(),
        geekpieToken: tokens.accessToken,
        geekpieExpiresAt: tokens.expiresAt,
        geekpieRefreshToken: tokens.refreshToken,
      );

      await _storage.saveSession(_session!);
      notifyListeners();
      final hook = onLogin;
      if (hook != null) {
        // Fire-and-forget: a sync pull failure must not break login UX.
        unawaited(hook());
      }
      return _session!;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> submitAccountDeletionRequest({
    required String expectedUserId,
  }) async {
    void checkIdentity() {
      if (expectedUserId.isEmpty || _session?.userId != expectedUserId) {
        throw const AccountDeletionRequestException('登录账号已变化，请重新打开注销页面。');
      }
    }

    checkIdentity();
    await tryRenewSession();
    checkIdentity();
    final token = _session?.geekpieToken;
    if (token == null || token.isEmpty) {
      throw const AccountDeletionRequestException('登录已失效，请重新登录。');
    }
    final uri = Uri.parse('$_baseUrl/account/deletion-request');
    final headers = {..._jsonHeaders(), 'Authorization': 'Bearer $token'};
    try {
      final response = await _http.post(
        uri,
        headers: headers,
        body: jsonEncode({'scope': 'geekpie-account'}),
        tag: 'accountDeletionRequest',
      ).timeout(const Duration(seconds: 30));
      checkIdentity();
      if (response.statusCode == 401) {
        throw const AccountDeletionRequestException('登录已失效，请重新登录后重试。');
      }
      if (response.statusCode == 429) {
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        throw AccountDeletionRequestException(
          seconds != null && seconds > 0
              ? '提交过于频繁，请在 $seconds 秒后重试。'
              : '提交过于频繁，请稍后重试。',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AccountDeletionRequestException('注销申请服务暂不可用，请稍后重试。');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] != true ||
          body['data'] is! Map<String, dynamic> ||
          (body['data'] as Map<String, dynamic>)['accepted'] != true) {
        throw const FormatException('Missing submission acknowledgement');
      }
    } on AccountDeletionRequestException {
      rethrow;
    } catch (_) {
      throw const AccountDeletionRequestException('未能确认申请已提交，请稍后重试；重复提交不会重复受理。');
    }
  }

  // -- Logout --

  Future<void> logout() async {
    _session = null;
    notifyListeners();
    await _storage.clearSession();
    if (onLogout != null) {
      try {
        await onLogout!();
      } catch (_) {}
    }
    notifyListeners();
  }

  // -- Private helpers --

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json; charset=UTF-8',
      };
}
