import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user_session.dart';
import 'api_base_url.dart';
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

  AuthService(this._storage, this._http, this._uniAuth);

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

  /// Renew the SSO access token via Casdoor's refresh-token grant. On
  /// success the rotated tokens are persisted into the session. Returns
  /// false (no throw) when there is no session, no refresh token, or the
  /// refresh fails — the caller decides whether to prompt for re-login.
  Future<bool> tryRenewSession() async {
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

  // -- Logout --

  Future<void> logout() async {
    await _storage.clearSession();
    _session = null;
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
