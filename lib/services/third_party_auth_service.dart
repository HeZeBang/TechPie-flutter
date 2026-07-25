import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/third_party_account.dart';
import 'api_base_url.dart';
import 'http_client.dart';
import 'session/session_node.dart';
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

  // SMS context for cpdaily binding flow (set by sendCpdailySmsCode).
  Map<String, dynamic>? _cpdailySmsContext;

  late final SessionTree _tree;

  ThirdPartyAuthService(this._storage, this._http) {
    _tree = SessionTree(
      persist: _persistAccount,
      http: _http,
      baseUrl: () => apiBaseUrl(_storage),
      persistDerived: _persistDerivedCookie,
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

  /// Convenience: the CpDaily session node — parent of [eamsNode] and
  /// [elearningNode]. Source of CASTGC / CpDaily cookies.
  SessionNode get cpdailyNode => _tree.cpdaily;

  /// Convenience: the EAMS downstream node (child of cpdaily).
  SessionNode get eamsNode => _tree.eams;

  /// Convenience: the eLearning downstream node (child of cpdaily).
  SessionNode get elearningNode => _tree.elearning;

  /// Convenience: the Gradescope top-level node.
  SessionNode get gradescopeNode => _tree.gradescope;

  /// Convenience: the Hydro top-level node.
  SessionNode get hydroNode => _tree.hydro;

  List<ThirdPartyPlatform> get boundPlatforms =>
      _accountsSnapshot.map((a) => a.platform).toList();
  Iterable<ThirdPartyAccount> get accounts => _accountsSnapshot;
  ThirdPartyAccount? account(ThirdPartyPlatform p) => _nodeAccount(p);

  List<ThirdPartyAccount> get _accountsSnapshot => [
        _tree.cpdaily.account,
        _tree.gradescope.account,
        _tree.hydro.account,
      ].whereType<ThirdPartyAccount>().toList();

  ThirdPartyAccount? _nodeAccount(ThirdPartyPlatform p) => switch (p) {
        ThirdPartyPlatform.cpdaily => _tree.cpdaily.account,
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

  /// Persist/clear a child node's derived cookie. Installed as the tree's
  /// [PersistDerivedCookie] callback so eams/elearning cookie minting and
  /// parent-renew cascades flow through storage.
  Future<void> _persistDerivedCookie(String nodeId, String? cookie) async {
    if (cookie == null) {
      await _storage.clearDerivedCookie(nodeId);
    } else {
      await _storage.saveDerivedCookie(nodeId, cookie);
    }
  }

  // -- CpDaily binding (single source of CASTGC / CpDaily session) --
  //
  // The cpdaily binding is the ONLY place CASTGC lives in the new
  // architecture. The primary GeekPie SSO session has no tgc/cookies; every
  // campus-system feature (schedule, blackboard, exam, oa-gym, webview
  // features) must read its CpDaily session through these accessors instead
  // of touching `AuthService.session` fields directly.

  /// True when a cpdaily binding exists. This is the gate every
  /// CASTGC-dependent feature must check before doing work.
  bool get hasCpdailyBinding => _tree.cpdaily.account != null;

  /// The bound cpdaily account, or null.
  ThirdPartyAccount? get cpdailyBinding => _tree.cpdaily.account;

  /// Cookie string for campus-system requests, always ending with
  /// `CASTGC=<tgc>` when a tgc is present (the form CpDaily/EAMS expects).
  /// Returns '' when there is no binding or no tgc — callers should treat
  /// that as "session unavailable".
  String cpdailyCookies() => _tree.cpdaily.cookieProvider?.cookies ?? '';

  /// Student id surfaced by the cpdaily binding, or '' if unbound.
  String get cpdailyStudentId => _tree.cpdaily.account?.sid ?? '';

  /// Best-effort renewal of the cpdaily binding's CpDaily session. Delegates
  /// to [SessionNode.renew], which is single-flighted: concurrent callers
  /// (two services hitting 401 at once) share ONE `/auth/renew` POST. On
  /// success the refreshed raw is persisted and listeners notified via the
  /// tree → [Service._onTreeChanged] path. Returns true on success.
  Future<void> initialize() async {
    final loaded = await _storage.loadAllThirdPartyAccounts();
    // Seed each node with its persisted account. setAccount routes to the
    // matching node and notifies (boot hydration — the sync hook is not wired
    // yet, so no cloud push fires).
    for (final acc in loaded) {
      _tree.setAccount(acc.platform, acc);
    }
    // Hydrate child node derived cookies so cold start can skip the SSO
    // bounce. These are best-effort — if stale, withCookie's 401 retry will
    // re-mint transparently.
    for (final id in const ['eams', 'elearning']) {
      final cookie = await _storage.loadDerivedCookie(id);
      _tree.setDerivedCookie(id, cookie);
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

    // cpdaily binds via the legacy 'egate' backend route; others use their id.
    final route = platform.apiPath;
    final resp = await _http.post(
      Uri.parse('$_baseUrl/auth/third-party/$route'),
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
    // Unbinding cpdaily invalidates all downstream derived cookies.
    if (platform == ThirdPartyPlatform.cpdaily) {
      for (final id in const ['eams', 'elearning']) {
        _tree.setDerivedCookie(id, null);
        await _storage.clearDerivedCookie(id);
      }
    }
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
    // Downstream derived cookies are invalidated when bindings are replaced.
    for (final id in const ['eams', 'elearning']) {
      _tree.setDerivedCookie(id, null);
      await _storage.clearDerivedCookie(id);
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

  // -- CpDaily SMS binding flow --

  /// Step 1: Send an SMS verification code for cpdaily binding.
  /// Reuses the existing /api/auth/mobile/send-sms endpoint.
  Future<void> sendCpdailySmsCode(String phone) async {
    final resp = await _http.post(
      Uri.parse('$_baseUrl/auth/mobile/send-sms'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({'phone': phone}),
      tag: 'cpdailySendSms',
    );

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.cpdaily,
        data['error'] as String? ?? 'Failed to send SMS',
      );
    }

    _cpdailySmsContext = data['context'] as Map<String, dynamic>?;
  }

  /// Step 2: Complete cpdaily binding via SMS verification code.
  Future<ThirdPartyAccount> bindCpdailySms({
    required String phone,
    required String code,
    bool autoRenew = false,
  }) async {
    if (_cpdailySmsContext == null) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.cpdaily,
        'Send SMS code first',
      );
    }

    // cpdaily binds via the legacy 'egate' backend route.
    final resp = await _http.post(
      Uri.parse('$_baseUrl/auth/third-party/egate'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({
        'phone': phone,
        'code': code,
        'context': _cpdailySmsContext,
      }),
      tag: 'cpdailyBindSms',
    );

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.cpdaily,
        'Invalid response (status ${resp.statusCode})',
      );
    }

    if (data['success'] != true) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.cpdaily,
        (data['error'] as String?) ?? 'login failed (${resp.statusCode})',
      );
    }

    final d = (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final token = d['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ThirdPartyBindException(
        ThirdPartyPlatform.cpdaily,
        'response missing token',
      );
    }

    final acc = ThirdPartyAccount(
      platform: ThirdPartyPlatform.cpdaily,
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
    _tree.setAccount(ThirdPartyPlatform.cpdaily, acc);
    _cpdailySmsContext = null;
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
      // cpdaily tokens are renewed via /api/auth/renew using stored tgc,
      // not via password re-authentication — skip here.
      if (acc.platform == ThirdPartyPlatform.cpdaily) continue;
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
    await _storage.clearAllDerivedCookies();
  }

  @override
  void dispose() {
    _tree.removeListener(_onTreeChanged);
    _tree.dispose();
    super.dispose();
  }
}
