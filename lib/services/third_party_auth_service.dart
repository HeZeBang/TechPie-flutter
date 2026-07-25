import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/third_party_account.dart';
import 'api_base_url.dart';
import 'http_client.dart';
import 'session/session_nodes.dart';
import 'session/session_tree.dart';
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

  bool _initialized = false;

  // SMS context for eGate binding flow (set by sendEgateSmsCode).
  Map<String, dynamic>? _egateSmsContext;

  late final SessionTree _tree;

  ThirdPartyAuthService(this._storage, this._http) {
    _tree = SessionTree(
      persist: _persistAccount,
      http: _http,
      baseUrl: () => apiBaseUrl(_storage),
    );
    // Tree node notifications propagate to this service's listeners (UI,
    // AssignmentService auto-refetch, etc.) and the cloud-sync push hook.
    _tree.addListener(_onTreeChanged);
  }

  String get _baseUrl => apiBaseUrl(_storage);

  bool get initialized => _initialized;

  // -- SessionTree access (new unified API) --

  /// The unified session tree. Callers that want node-level control (e.g.
  /// [SessionTree.withCookie] for 401-renew-retry) go through here.
  SessionTree get sessionTree => _tree;

  /// Convenience: the CpDaily (eGate) session node — parent of [idsNode].
  CpdailySessionNode get egateNode => _tree.egate;

  /// Convenience: the IDS session node — child of [egateNode], refreshed via
  /// the CpDaily session.
  IdsSessionNode get idsNode => _tree.ids;

  List<ThirdPartyPlatform> get boundPlatforms =>
      _accountsSnapshot.map((a) => a.platform).toList();
  Iterable<ThirdPartyAccount> get accounts => _accountsSnapshot;
  ThirdPartyAccount? account(ThirdPartyPlatform p) => _nodeAccount(p);

  List<ThirdPartyAccount> get _accountsSnapshot => [
        _tree.egate.account,
        _tree.gradescope.account,
        _tree.hydro.account,
      ].whereType<ThirdPartyAccount>().toList();

  ThirdPartyAccount? _nodeAccount(ThirdPartyPlatform p) => switch (p) {
        ThirdPartyPlatform.egate => _tree.egate.account,
        ThirdPartyPlatform.gradescope => _tree.gradescope.account,
        ThirdPartyPlatform.hydro => _tree.hydro.account,
      };

  /// Post-construction hook fired after any binding mutation (bind / unbind /
  /// raw update / replaceAll / node-initiated renew). Wired by main.dart to
  /// [SyncService.pushIfDue] so the cloud backup stays current. Null until
  /// wired; safe to call.
  Future<void> Function()? onBindingsChanged;

  void _onTreeChanged() {
    // A node changed (renew / setAccount) — re-notify our listeners and push
    // to cloud sync. This is the single funnel for all mutations now.
    notifyListeners();
    final hook = onBindingsChanged;
    if (hook != null) {
      unawaited(hook());
    }
  }

  /// Persist a (possibly refreshed) account into secure storage AND sync the
  /// matching [SessionNode]'s in-memory state. Installed as the tree's
  /// [PersistAccount] callback so node-initiated renews flow through here.
  Future<void> _persistAccount(ThirdPartyAccount updated) async {
    await _storage.saveThirdPartyAccount(updated);
    // The node already updated its own _account before calling persist; we
    // only need storage + notification here (notification fires via the tree
    // listener → _onTreeChanged).
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
  bool get hasEgateBinding => _tree.egate.account != null;

  /// The bound eGate account, or null.
  ThirdPartyAccount? get egateBinding => _tree.egate.account;

  /// Cookie string for campus-system requests, always ending with
  /// `CASTGC=<tgc>` when a tgc is present (the form CpDaily/EAMS expects).
  /// Returns '' when there is no binding or no tgc — callers should treat
  /// that as "session unavailable".
  String egateCookies() => _tree.egate.cookieProvider?.cookies ?? '';

  /// Student id surfaced by the eGate binding, or '' if unbound.
  String get egateStudentId => _tree.egate.account?.sid ?? '';

  /// Best-effort renewal of the eGate binding's CpDaily session. Delegates to
  /// [CpdailySessionNode.renew], which is single-flighted: concurrent callers
  /// (two services hitting 401 at once) share ONE `/auth/renew` POST. On
  /// success the refreshed raw is persisted and listeners notified via the
  /// tree → [Service._onTreeChanged] path. Returns true on success.
  Future<bool> renewEgateBinding() => _tree.egate.renew();

  Future<void> initialize() async {
    final loaded = await _storage.loadAllThirdPartyAccounts();
    // Seed each node with its persisted account. setAccount routes to the
    // matching node and notifies (boot hydration — the sync hook is not wired
    // yet, so no cloud push fires).
    for (final acc in loaded) {
      _tree.setAccount(acc.platform, acc);
    }
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
    _tree.setAccount(platform, acc);
    return acc;
  }

  Future<void> unbind(ThirdPartyPlatform platform) async {
    _tree.setAccount(platform, null);
    await _storage.clearThirdPartyAccount(platform);
  }
  /// Replace the entire in-memory + persisted binding set in one shot. Used by
  /// [SyncService.pull] to restore a cloud-fetched snapshot: clears every
  /// existing platform binding, writes each entry in [next] to secure storage,
  /// and rebuilds the in-memory map. Fires a single notification.
  Future<void> replaceAll(List<ThirdPartyAccount> next) async {
    // Clear storage for every platform first.
    for (final p in ThirdPartyPlatform.values) {
      await _storage.clearThirdPartyAccount(p);
    }
    // Then seed each node + persist. setAccount notifies per-node; the tree
    // listener funnels into a single _onTreeChanged (throttled by SyncService).
    final byPlatform = {
      for (final a in next) a.platform: a,
    };
    for (final p in ThirdPartyPlatform.values) {
      _tree.setAccount(p, byPlatform[p]);
      final a = byPlatform[p];
      if (a != null) await _storage.saveThirdPartyAccount(a);
    }
  }

  /// Update the raw data of a bound account (e.g. after CpDaily session renewal).
  Future<void> updateRaw(
    ThirdPartyPlatform platform,
    Map<String, dynamic> newRaw,
  ) async {
    final acc = _nodeAccount(platform);
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
    _tree.setAccount(platform, updated);
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
    _tree.setAccount(ThirdPartyPlatform.egate, acc);
    _egateSmsContext = null;
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
    final snapshot = _accountsSnapshot;
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
    for (final p in ThirdPartyPlatform.values) {
      _tree.setAccount(p, null);
    }
    await _storage.clearAllThirdPartyAccounts();
  }

  @override
  void dispose() {
    _tree.removeListener(_onTreeChanged);
    _tree.dispose();
    super.dispose();
  }
}
