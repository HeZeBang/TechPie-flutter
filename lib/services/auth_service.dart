import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user_session.dart';
import 'api_base_url.dart';
import 'http_client.dart';
import 'storage_service.dart';

class AuthService extends ChangeNotifier {
  final StorageService _storage;
  final LoggingHttpClient _http;

  UserSession? _session;
  bool _loading = false;

  // Context returned by send-sms, needed for mobile/login
  Map<String, dynamic>? _smsContext;

  // Injected post-construction to check third-party bindings.
  // avoids circular construction with ThirdPartyAuthService.
  bool Function()? _hasEgateBinding;

  String get _baseUrl => apiBaseUrl(_storage);

  UserSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get loading => _loading;
  bool get hasEgateBinding => _hasEgateBinding?.call() ?? false;

  // Optional callback fired after primary-account logout so dependent
  // services (e.g. third-party bindings) can clear themselves. Injected
  // post-construction from main.dart to avoid circular construction.
  Future<void> Function()? onLogout;

  AuthService(this._storage, this._http);

  /// Inject the eGate binding checker (called post-construction from main.dart).
  void setEgateBindingChecker(bool Function() checker) {
    _hasEgateBinding = checker;
  }

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

  Future<bool> tryRenewSession() async {
    if (_session == null) return false;
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/renew'),
        headers: _jsonHeaders(),
        body: jsonEncode({
          'sessionToken': _session!.sessionToken,
          'tgc': _session!.tgc,
          'userId': _session!.userId,
          'tenantId': _session!.tenantId,
        }),
        tag: 'tokenRenew',
      );

      if (resp.statusCode != 200) return false;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) return false;

      _session = _session!.copyWith(
        sessionToken: data['sessionToken'] as String? ?? _session!.sessionToken,
        tgc: data['tgc'] as String? ?? _session!.tgc,
        userId: data['userId'] as String? ?? _session!.userId,
        userName: data['name'] as String? ?? _session!.userName,
        tenantId: data['tenantId'] as String? ?? _session!.tenantId,
        cookies: data['cookies'] as String? ?? _session!.cookies,
        studentId: data['openId'] as String? ?? _session!.studentId,
      );
      await _storage.saveSession(_session!);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Renew CpDaily session using raw data from a third-party binding (e.g.
  /// eGate). Returns the refreshed raw map on success, or null on failure.
  /// Does NOT mutate [_session] — the caller is responsible for persisting
  /// the updated raw data back into the ThirdPartyAccount.
  Future<Map<String, dynamic>?> tryRenewCpDailySession(
    Map<String, dynamic> raw,
  ) async {
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/renew'),
        headers: _jsonHeaders(),
        body: jsonEncode({
          'sessionToken': raw['sessionToken'] ?? '',
          'tgc': raw['tgc'] ?? '',
          'userId': raw['userId'] ?? '',
          'tenantId': raw['tenantId'] ?? '',
        }),
        tag: 'cpDailyRenew',
      );

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) return null;

      return {
        ...raw,
        'sessionToken': data['sessionToken'] as String? ?? raw['sessionToken'],
        'tgc': data['tgc'] as String? ?? raw['tgc'],
        'userId': data['userId'] as String? ?? raw['userId'],
        'tenantId': data['tenantId'] as String? ?? raw['tenantId'],
        'cookies': data['cookies'] as String? ?? raw['cookies'],
      };
    } catch (_) {
      return null;
    }
  }

  // -- SMS Login Flow --

  Future<void> sendSmsCode(String phone) async {
    final resp = await _http.post(
      Uri.parse('$_baseUrl/auth/mobile/send-sms'),
      headers: _jsonHeaders(),
      body: jsonEncode({'phone': phone}),
      tag: 'sendSms',
    );

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] as String? ?? 'Failed to send SMS');
    }

    // Store context for the login step
    _smsContext = data['context'] as Map<String, dynamic>?;
  }

  Future<UserSession> smsLogin(String phone, String code) async {
    if (_smsContext == null) {
      throw Exception('Send SMS code first');
    }

    _loading = true;
    notifyListeners();
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/mobile/login'),
        headers: _jsonHeaders(),
        body: jsonEncode({
          'phone': phone,
          'code': code,
          'context': _smsContext,
        }),
        tag: 'smsLogin',
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error'] as String? ?? 'Login failed');
      }

      final loginResult =
          data['loginResult'] as Map<String, dynamic>? ?? const {};

      _session = UserSession(
        sessionToken: data['sessionToken'] as String? ?? '',
        tgc: data['tgc'] as String? ?? '',
        userId: data['userId'] as String? ?? '',
        userName: loginResult['name'] as String? ?? '',
        schoolName: '上海科技大学',
        tenantId: data['tenantId'] as String? ?? '',
        phoneNumber: phone,
        cookies: data['cookies'] as String? ?? '',
        studentId: loginResult['openId'] as String? ?? '',
        createdAt: DateTime.now(),
      );

      _smsContext = null;
      await _storage.saveSession(_session!);
      await _storage.setCachedPhone(phone);
      notifyListeners();
      return _session!;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // -- eGate Login Flow --

  Future<UserSession> egateLogin(String username, String password) async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/egate'),
        headers: _jsonHeaders(),
        body: jsonEncode({'username': username, 'password': password}),
        tag: 'egateLogin',
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error'] as String? ?? 'Login failed');
      }

      final loginResult =
          data['loginResult'] as Map<String, dynamic>? ?? const {};

      _session = UserSession(
        sessionToken: data['sessionToken'] as String? ?? '',
        tgc: data['tgc'] as String? ?? '',
        userId: data['userId'] as String? ?? username,
        userName: loginResult['name'] as String? ?? '',
        schoolName: '上海科技大学',
        tenantId: data['tenantId'] as String? ?? '',
        phoneNumber: '',
        cookies: data['cookies'] as String? ?? '',
        createdAt: DateTime.now(),
        studentId: loginResult['openId'] as String? ?? '',
      );

      await _storage.saveSession(_session!);
      notifyListeners();
      return _session!;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // -- GeekPie Uni-Auth Login --

  Future<UserSession> geekpieLogin(String geekpieToken) async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/geekpie'),
        headers: _jsonHeaders(),
        body: jsonEncode({'token': geekpieToken}),
        tag: 'geekpieLogin',
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error'] as String? ?? 'Login failed');
      }

      _session = UserSession(
        sessionToken: '',
        tgc: '',
        userId: data['userId'] as String? ?? '',
        userName: data['userName'] as String? ?? '',
        schoolName: '上海科技大学',
        tenantId: '',
        phoneNumber: '',
        cookies: '',
        studentId: '',
        createdAt: DateTime.now(),
        geekpieToken: geekpieToken,
        geekpieExpiresAt: data['expiresAt'] as String?,
      );

      await _storage.saveSession(_session!);
      notifyListeners();
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
