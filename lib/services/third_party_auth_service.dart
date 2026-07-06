import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/third_party_account.dart';
import 'api_base_url.dart';
import 'http_client.dart';
import 'storage_service.dart';

class ThirdPartyBindException implements Exception {
  final ThirdPartyPlatform platform;
  final String message;
  ThirdPartyBindException(this.platform, this.message);
  @override
  String toString() => '${platform.label}: $message';
}

class ThirdPartyAuthService extends ChangeNotifier {
  final StorageService _storage;
  final LoggingHttpClient _http;

  final Map<ThirdPartyPlatform, ThirdPartyAccount> _accounts = {};
  bool _initialized = false;

  // SMS context for eGate binding flow (set by sendEgateSmsCode).
  Map<String, dynamic>? _egateSmsContext;

  ThirdPartyAuthService(this._storage, this._http);

  String get _baseUrl => apiBaseUrl(_storage);

  bool get initialized => _initialized;
  List<ThirdPartyPlatform> get boundPlatforms => _accounts.keys.toList();
  Iterable<ThirdPartyAccount> get accounts => _accounts.values;
  ThirdPartyAccount? account(ThirdPartyPlatform p) => _accounts[p];

  Future<void> initialize() async {
    final loaded = await _storage.loadAllThirdPartyAccounts();
    _accounts
      ..clear()
      ..addEntries(loaded.map((a) => MapEntry(a.platform, a)));
    _initialized = true;
    notifyListeners();
  }

  Future<ThirdPartyAccount> bind({
    required ThirdPartyPlatform platform,
    required String account,
    required String password,
    String? hydroOrigin,
    List<String>? hydroDomains,
    bool autoRenew = false,
  }) async {
    final body = <String, dynamic>{
      'account': account,
      'password': password,
    };
    if (platform == ThirdPartyPlatform.hydro &&
        hydroOrigin != null &&
        hydroOrigin.isNotEmpty) {
      body['args'] = {'url': hydroOrigin};
    }

    final resp = await _http.post(
      Uri.parse('$_baseUrl/auth/third-party/${platform.id}'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(body),
      tag: 'thirdPartyBind:${platform.id}',
    );

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ThirdPartyBindException(
        platform,
        'Invalid response (status ${resp.statusCode})',
      );
    }

    if (data['success'] != true) {
      throw ThirdPartyBindException(
        platform,
        (data['error'] as String?) ?? 'login failed (${resp.statusCode})',
      );
    }

    final d = (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final token = d['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ThirdPartyBindException(platform, 'response missing token');
    }

    final acc = ThirdPartyAccount(
      platform: platform,
      account: account,
      sid: d['sid'] as String?,
      name: d['name'] as String?,
      email: d['email'] as String?,
      token: token,
      expire: (d['expire'] as num?)?.toInt(),
      raw: (d['raw'] as Map?)?.cast<String, dynamic>() ?? const {},
      hydroOrigin: platform == ThirdPartyPlatform.hydro
          ? (hydroOrigin?.isNotEmpty == true ? hydroOrigin : null)
          : null,
      hydroDomains: platform == ThirdPartyPlatform.hydro
          ? (hydroDomains == null || hydroDomains.isEmpty ? null : hydroDomains)
          : null,
      boundAt: DateTime.now(),
      autoRenew: autoRenew,
      password: autoRenew ? password : null,
    );

    await _storage.saveThirdPartyAccount(acc);
    _accounts[platform] = acc;
    notifyListeners();
    return acc;
  }

  Future<void> unbind(ThirdPartyPlatform platform) async {
    _accounts.remove(platform);
    await _storage.clearThirdPartyAccount(platform);
    notifyListeners();
  }

  /// Update the raw data of a bound account (e.g. after CpDaily session renewal).
  Future<void> updateRaw(
    ThirdPartyPlatform platform,
    Map<String, dynamic> newRaw,
  ) async {
    final acc = _accounts[platform];
    if (acc == null) return;
    final updated = ThirdPartyAccount(
      platform: acc.platform,
      account: acc.account,
      sid: acc.sid,
      name: acc.name,
      email: acc.email,
      token: acc.token,
      expire: acc.expire,
      raw: newRaw,
      hydroOrigin: acc.hydroOrigin,
      hydroDomains: acc.hydroDomains,
      boundAt: acc.boundAt,
      autoRenew: acc.autoRenew,
      password: acc.password,
    );
    await _storage.saveThirdPartyAccount(updated);
    _accounts[platform] = updated;
    notifyListeners();
  }

  // -- eGate SMS binding flow --

  /// Step 1: Send an SMS verification code for eGate binding.
  /// Reuses the existing /api/auth/mobile/send-sms endpoint.
  Future<void> sendEgateSmsCode(String phone) async {
    final resp = await _http.post(
      Uri.parse('$_baseUrl/auth/mobile/send-sms'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({'phone': phone}),
      tag: 'egateSendSms',
    );

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.egate,
        data['error'] as String? ?? 'Failed to send SMS',
      );
    }

    _egateSmsContext = data['context'] as Map<String, dynamic>?;
  }

  /// Step 2: Complete eGate binding via SMS verification code.
  Future<ThirdPartyAccount> bindEgateSms({
    required String phone,
    required String code,
    bool autoRenew = false,
  }) async {
    if (_egateSmsContext == null) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.egate,
        'Send SMS code first',
      );
    }

    final resp = await _http.post(
      Uri.parse('$_baseUrl/auth/third-party/egate'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({
        'phone': phone,
        'code': code,
        'context': _egateSmsContext,
      }),
      tag: 'egateBindSms',
    );

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.egate,
        'Invalid response (status ${resp.statusCode})',
      );
    }

    if (data['success'] != true) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.egate,
        (data['error'] as String?) ?? 'login failed (${resp.statusCode})',
      );
    }

    final d = (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final token = d['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.egate,
        'response missing token',
      );
    }

    final acc = ThirdPartyAccount(
      platform: ThirdPartyPlatform.egate,
      account: phone,
      sid: d['sid'] as String?,
      name: d['name'] as String?,
      email: d['email'] as String?,
      token: token,
      expire: (d['expire'] as num?)?.toInt(),
      raw: (d['raw'] as Map?)?.cast<String, dynamic>() ?? const {},
      boundAt: DateTime.now(),
      autoRenew: false, // SMS binding does not support auto-renew
    );

    await _storage.saveThirdPartyAccount(acc);
    _accounts[ThirdPartyPlatform.egate] = acc;
    _egateSmsContext = null;
    notifyListeners();
    return acc;
  }

  /// Boot-time best-effort renewal: for each bound account whose token is
  /// either expired or expires within [window] (default 48h) AND has
  /// auto-renew enabled with stored credentials, re-authenticate.
  /// Returns the list of platforms whose renewal attempt failed (so the
  /// caller can surface a single aggregated toast); platforms that didn't
  /// need renewal are not included.
  Future<List<ThirdPartyPlatform>> autoRenewIfNeeded({
    Duration window = const Duration(hours: 48),
  }) async {
    final cutoff = DateTime.now().add(window);
    final snapshot = _accounts.values.toList();
    final failed = <ThirdPartyPlatform>[];
    for (final acc in snapshot) {
      if (!acc.autoRenew) continue;
      // eGate tokens are renewed via /api/auth/renew using stored tgc,
      // not via password re-authentication — skip here.
      if (acc.platform == ThirdPartyPlatform.egate) continue;
      final pw = acc.password;
      if (pw == null || pw.isEmpty) continue;
      final at = acc.expireAt;
      if (at == null) continue;
      if (at.isAfter(cutoff)) continue;
      try {
        await bind(
          platform: acc.platform,
          account: acc.account,
          password: pw,
          hydroOrigin: acc.hydroOrigin,
          hydroDomains: acc.hydroDomains,
          autoRenew: true,
        );
      } catch (_) {
        failed.add(acc.platform);
      }
    }
    return failed;
  }

  Future<void> clearAll() async {
    _accounts.clear();
    await _storage.clearAllThirdPartyAccounts();
    notifyListeners();
  }
}
