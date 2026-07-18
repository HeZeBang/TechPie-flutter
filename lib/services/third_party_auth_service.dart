import 'dart:async';
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

  /// Post-construction hook fired after any binding mutation (bind / unbind /
  /// raw update / replaceAll). Wired by main.dart to [SyncService.pushIfDue]
  /// so the cloud backup stays current. Null until wired; safe to call.
  Future<void> Function()? onBindingsChanged;

  void _notifyChanged() {
    notifyListeners();
    final hook = onBindingsChanged;
    if (hook != null) {
      // Fire-and-forget; the hook is throttled and swallows its own errors.
      unawaited(hook());
    }
  }

  // -- eGate binding (single source of CASTGC / CpDaily session) --
  //
  // The eGate binding is the ONLY place CASTGC lives in the new architecture.
  // The primary GeekPie SSO session has no tgc/cookies; every campus-system
  // feature (schedule, blackboard, exam, oa-gym, webview features) must read
  // its CpDaily session through these accessors instead of touching
  // `AuthService.session` fields directly.

  /// True when an eGate / IDS binding exists. This is the gate every
  /// CASTGC-dependent feature must check before doing work.
  bool get hasEgateBinding => _accounts[ThirdPartyPlatform.egate] != null;

  /// The bound eGate account, or null.
  ThirdPartyAccount? get egateBinding => _accounts[ThirdPartyPlatform.egate];

  /// Cookie string for campus-system requests, always ending with
  /// `CASTGC=<tgc>` when a tgc is present (the form CpDaily/EAMS expects).
  /// Returns '' when there is no binding or no tgc — callers should treat
  /// that as "session unavailable".
  String egateCookies() {
    final acc = _accounts[ThirdPartyPlatform.egate];
    if (acc == null) return '';
    final raw = acc.raw;
    final baseCookies = (raw['cookies'] as String?) ?? '';
    final tgc = (raw['tgc'] as String?) ?? '';
    return tgc.isEmpty
        ? baseCookies
        : (baseCookies.isNotEmpty
            ? '$baseCookies; CASTGC=$tgc'
            : 'CASTGC=$tgc');
  }

  /// Student id surfaced by the eGate binding, or '' if unbound.
  String get egateStudentId =>
      _accounts[ThirdPartyPlatform.egate]?.sid ?? '';

  /// Best-effort renewal of the eGate binding's CpDaily session via
  /// `/api/auth/renew`. On success the refreshed raw data is persisted back
  /// into the binding and listeners are notified. Returns true on success.
  Future<bool> renewEgateBinding() async {
    final acc = _accounts[ThirdPartyPlatform.egate];
    if (acc == null) return false;
    try {
      final resp = await _http.post(
        Uri.parse('$_baseUrl/auth/renew'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'sessionToken': acc.raw['sessionToken'] ?? '',
          'tgc': acc.raw['tgc'] ?? '',
          'userId': acc.raw['userId'] ?? '',
          'tenantId': acc.raw['tenantId'] ?? '',
        }),
        tag: 'egateCpDailyRenew',
      );

      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) return false;

      await updateRaw(
        ThirdPartyPlatform.egate,
        {
          ...acc.raw,
          'sessionToken':
              data['sessionToken'] as String? ?? acc.raw['sessionToken'] ?? '',
          'tgc': data['tgc'] as String? ?? acc.raw['tgc'] ?? '',
          'userId': data['userId'] as String? ?? acc.raw['userId'] ?? '',
          'tenantId':
              data['tenantId'] as String? ?? acc.raw['tenantId'] ?? '',
          'cookies': data['cookies'] as String? ?? acc.raw['cookies'] ?? '',
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize() async {
    final loaded = await _storage.loadAllThirdPartyAccounts();
    _accounts
      ..clear()
      ..addEntries(loaded.map((a) => MapEntry(a.platform, a)));
    _initialized = true;
    // Boot hydration is not a user-driven mutation — notify listeners but do
    // NOT trigger a cloud push (the hook is not wired yet at this point, and
    // a pull may follow that should take precedence).
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
    _notifyChanged();
    return acc;
  }

  Future<void> unbind(ThirdPartyPlatform platform) async {
    _accounts.remove(platform);
    await _storage.clearThirdPartyAccount(platform);
    _notifyChanged();
  }

  /// Replace the entire in-memory + persisted binding set in one shot. Used by
  /// [SyncService.pull] to restore a cloud-fetched snapshot: clears every
  /// existing platform binding, writes each entry in [next] to secure storage,
  /// and rebuilds the in-memory map. Fires a single notification.
  Future<void> replaceAll(List<ThirdPartyAccount> next) async {
    for (final p in ThirdPartyPlatform.values) {
      await _storage.clearThirdPartyAccount(p);
    }
    _accounts
      ..clear()
      ..addEntries(next.map((a) => MapEntry(a.platform, a)));
    for (final a in next) {
      await _storage.saveThirdPartyAccount(a);
    }
    _notifyChanged();
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
    _notifyChanged();
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
    _notifyChanged();
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
    _notifyChanged();
  }
}
