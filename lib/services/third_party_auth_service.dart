import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/renew_status.dart';
import '../models/third_party_account.dart';
import 'api_base_url.dart';
import 'http_client.dart';
import 'session/session_node.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';

/// Every session-node id, top-level and derived, in a stable order. Used to
/// bulk-load persisted renew status at boot.
const List<String> _allSessionNodeIds = [
  'cpdaily',
  'gradescope',
  'hydro',
  'eams',
  'elearning',
  'egateApp',
];

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
  bool _suppressSyncPush = false;
  // Set by a renew-success call site (via _persistAccount/bind's `force`
  // param) just before triggering _tree.setAccount, so the resulting
  // _onTreeChanged() call knows to bypass the pushIfDue throttle. Consumed
  // (reset to false) the moment _onTreeChanged reads it.
  bool _pendingForcePush = false;
  // SMS context for cpdaily binding flow (set by sendCpdailySmsCode).
  Map<String, dynamic>? _cpdailySmsContext;

  late final SessionTree _tree;
  // Stable per-device id, loaded in [initialize]. Stamped onto every locally
  // mutated account so the cloud-sync LWW merge converges.
  String _deviceId = '';

  // Renew status per session-node id (cpdaily/gradescope/hydro/eams/
  // elearning), for the linked-accounts status indicator. Loaded at boot,
  // updated in-memory + persisted on every renew attempt. Local-only.
  final Map<String, RenewStatus> _renewStatuses = {};
  RenewStatus? renewStatus(String nodeId) => _renewStatuses[nodeId];

  ThirdPartyAuthService(this._storage, this._http) {
    _tree = SessionTree(
      persist: _persistAccount,
      http: _http,
      baseUrl: () => apiBaseUrl(_storage),
      persistDerived: _persistDerivedCookie,
      recordRenewStatus: _recordRenewStatus,
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

  /// Convenience: the egate-app (xshdapp activity check-in) downstream node
  /// (child of cpdaily).
  SessionNode get egateAppNode => _tree.egateApp;

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
  /// wired; safe to call. When [force] is true the caller (unbind/clearAll)
  /// wants the push to bypass the throttle so a removal is immediately
  /// reflected in the cloud blob.
  Future<void> Function({bool force})? onBindingsChanged;
  /// Hook fired when a platform is deliberately unbound. Wired by
  /// [SyncService] to record a tombstone so the deletion survives the next
  /// LWW merge (instead of being resurrected by an older remote copy).
  /// Null until wired; safe to call.
  void Function(ThirdPartyPlatform platform)? onUnbind;

  void _onTreeChanged({bool force = false}) {
    // While [applySyncMerge] is replaying a merged snapshot, suppress ALL
    // downstream effects — the merge path notifies once at the end and
    // writes the merged envelope itself. This avoids an N+1 notify storm
    // (one per setAccount) that would each cascade into
    // AssignmentService.fetchAssignments + SyncService.pushIfDue.
    if (_suppressSyncPush) return;
    // A renew-success call site (_persistAccount/bind) may have requested a
    // forced push just before this notification fired.
    final effectiveForce = force || _pendingForcePush;
    _pendingForcePush = false;
    // A node changed (renew / setAccount) — re-notify our listeners and push
    // to cloud sync. This is the single funnel for all mutations now.
    notifyListeners();
    final hook = onBindingsChanged;
    if (hook != null) {
      unawaited(hook(force: effectiveForce));
    }
  }

  /// Persist a (possibly refreshed) account into secure storage AND sync the
  /// matching [SessionNode]'s in-memory state. Installed as the tree's
  /// [PersistAccount] callback so node-initiated renews flow through here.
  /// [force] requests the cloud-sync push bypass its throttle — set by
  /// [SessionNode]'s renew methods since a successful renew must not wait
  /// for the next throttle window.
  Future<void> _persistAccount(
    ThirdPartyAccount updated, {
    bool force = false,
  }) async {
    // Stamp the renewed/refreshed account with this device's id + a fresh
    // updatedAt so the cloud-sync LWW merge treats it as the newest version.
    final touched = _touch(updated);
    await _storage.saveThirdPartyAccount(touched);
    if (force) _pendingForcePush = true;
    // Re-sync the node's in-memory copy so UI + cookieProvider see the
    // stamped version. setAccount notifies; _onTreeChanged funnels it.
    _tree.setAccount(touched.platform, touched);
  }

  /// Persist a session node's renew outcome (in-memory + storage) for the
  /// linked-accounts status indicator. Installed as the tree's
  /// [PersistRenewStatus] callback.
  Future<void> _recordRenewStatus(String nodeId, RenewStatus status) async {
    _renewStatuses[nodeId] = status;
    await _storage.saveRenewStatus(nodeId, status);
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

  /// Stamp [acc] with this device's id + current time, for LWW merge.
  ThirdPartyAccount _touch(ThirdPartyAccount acc) {
    return acc.copyWith(updatedAt: DateTime.now(), deviceId: _deviceId);
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
    _deviceId = await _storage.ensureDeviceId();
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
    for (final id in const ['eams', 'elearning', 'egateApp']) {
      final cookie = await _storage.loadDerivedCookie(id);
      _tree.setDerivedCookie(id, cookie);
    }
    // Hydrate the renew-status indicator cache (+ each node's in-memory
    // copy) so the linked-accounts UI can render a status dot immediately.
    for (final id in _allSessionNodeIds) {
      final status = _storage.loadRenewStatus(id);
      if (status != null) _renewStatuses[id] = status;
      _sessionNode(id)?.seedRenewStatus(status);
    }
    _initialized = true;
    notifyListeners();
  }

  /// Look up a [SessionNode] by its stable string id (matches
  /// [ThirdPartyPlatform.id] for top-level nodes, plus 'eams'/'elearning').
  SessionNode? _sessionNode(String nodeId) => switch (nodeId) {
        'cpdaily' => _tree.cpdaily,
        'gradescope' => _tree.gradescope,
        'hydro' => _tree.hydro,
        'eams' => _tree.eams,
        'elearning' => _tree.elearning,
        'egateApp' => _tree.egateApp,
        _ => null,
      };

  Future<ThirdPartyAccount> bind({
    required ThirdPartyPlatform platform,
    required String account,
    required String password,
    String? hydroOrigin,
    List<String>? hydroDomains,
    bool autoRenew = false,
    // Requests the cloud-sync push bypass its throttle. Set by
    // [autoRenewIfNeeded] since a successful background auto-renew must not
    // wait for the next throttle window.
    bool forceSyncPush = false,
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

    final touched = _touch(acc);
    await _storage.saveThirdPartyAccount(touched);
    if (forceSyncPush) _pendingForcePush = true;
    _tree.setAccount(platform, touched);
    return touched;
  }

  Future<void> unbind(ThirdPartyPlatform platform) async {
    _tree.setAccount(platform, null);
    await _storage.clearThirdPartyAccount(platform);
    // Unbinding cpdaily invalidates all downstream derived cookies.
    if (platform == ThirdPartyPlatform.cpdaily) {
      for (final id in const ['eams', 'elearning', 'egateApp']) {
        _tree.setDerivedCookie(id, null);
        await _storage.clearDerivedCookie(id);
      }
    }
    // Record a tombstone for the cloud-sync merge so this deletion is not
    // resurrected by an older remote copy on the next pull.
    final unbindHook = onUnbind;
    if (unbindHook != null) unbindHook(platform);
    // Force-push so the removal is immediately reflected in the cloud blob,
    // bypassing the pushIfDue throttle. Without this, a throttled skip would
    // leave the stale binding in the cloud and the next boot's pull would
    // restore it.
    _onTreeChanged(force: true);
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
    for (final id in const ['eams', 'elearning', 'egateApp']) {
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

  /// Apply a merged account set coming from the cloud-sync LWW merge. For
  /// each platform: if a kept account is present, persist + set it; if the
  /// platform is in [removed], clear it. Unlike [replaceAll], this does NOT
  /// clear every platform first — it writes per-platform diffs and skips the
  /// cloud-sync push hook (the sync path pushes the merged envelope itself),
  /// avoiding a redundant throttled push right after an explicit one.
  Future<void> applySyncMerge(
    List<ThirdPartyAccount> kept,
    Set<ThirdPartyPlatform> removed,
  ) async {
    _suppressSyncPush = true;
    try {
      final byPlatform = {
        for (final a in kept) a.platform: a,
      };
      for (final p in ThirdPartyPlatform.values) {
        final next = byPlatform[p];
        final cur = _nodeAccount(p);
        // Skip no-op writes: if the merged account equals the current one
        // (same token, same updatedAt), don't touch storage or fire notifies.
        if (next != null && cur != null && _accountEqual(cur, next)) continue;
        if (next == null && cur == null) continue;
        if (next != null) {
          await _storage.saveThirdPartyAccount(next);
          _tree.setAccount(p, next);
        } else {
          // Clearing cpdaily invalidates downstream derived cookies.
          if (p == ThirdPartyPlatform.cpdaily && cur != null) {
            for (final id in const ['eams', 'elearning', 'egateApp']) {
              _tree.setDerivedCookie(id, null);
              await _storage.clearDerivedCookie(id);
            }
          }
          _tree.setAccount(p, null);
          await _storage.clearThirdPartyAccount(p);
        }
      }
    } finally {
      _suppressSyncPush = false;
    }
    // One notification for the whole merge.
    notifyListeners();
  }

  /// Cheap structural equality used by [applySyncMerge] to skip no-op writes.
  static bool _accountEqual(ThirdPartyAccount a, ThirdPartyAccount b) {
    return a.token == b.token &&
        a.account == b.account &&
        a.expire == b.expire &&
        a.updatedAt == b.updatedAt &&
        a.deviceId == b.deviceId;
  }

  /// Update the raw data of a bound account (e.g. after CpDaily session renewal).
  Future<void> updateRaw(
    ThirdPartyPlatform platform,
    Map<String, dynamic> newRaw,
  ) async {
    final acc = _nodeAccount(platform);
    if (acc == null) return;
    final touched = _touch(acc.copyWith(raw: newRaw));
    await _storage.saveThirdPartyAccount(touched);
    _tree.setAccount(platform, touched);
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

    final touched = _touch(acc);
    await _storage.saveThirdPartyAccount(touched);
    _tree.setAccount(ThirdPartyPlatform.cpdaily, touched);
    _cpdailySmsContext = null;
    return touched;
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
          forceSyncPush: true,
        );
        await _recordRenewStatus(
          acc.platform.id,
          RenewStatus(at: DateTime.now(), success: true),
        );
      } catch (e) {
        failed.add(acc.platform);
        await _recordRenewStatus(
          acc.platform.id,
          RenewStatus(at: DateTime.now(), success: false, error: '$e'),
        );
      }
    }
    return failed;
  }

  Future<void> clearAll() async {
    final unbindHook = onUnbind;
    for (final p in ThirdPartyPlatform.values) {
      if (_nodeAccount(p) != null) {
        if (unbindHook != null) unbindHook(p);
      }
      _tree.setAccount(p, null);
    }
    await _storage.clearAllThirdPartyAccounts();
    await _storage.clearAllDerivedCookies();
    _onTreeChanged(force: true);
  }

  @override
  void dispose() {
    _tree.removeListener(_onTreeChanged);
    _tree.dispose();
    super.dispose();
  }
}
