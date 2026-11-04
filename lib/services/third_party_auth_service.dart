import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../features/campus_card/core/async_mutex.dart';
import '../models/ids_passkey.dart';
import '../models/renew_status.dart';
import '../models/third_party_account.dart';
import 'api_base_url.dart';
import 'campus_web_session.dart';
import 'http_client.dart';
import 'ids/ids_client.dart';
import 'session/session_node.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';
import 'sync_envelope.dart' show SyncTombstone, nextSyncTimestamp;

/// Every session-node id, top-level and derived, in a stable order. Used to
/// bulk-load persisted renew status at boot.
const List<String> _allSessionNodeIds = [
  'ids',
  'gradescope',
  'hydro',
  'eams',
  'elearning',
  'egateApp',
  'oa',
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
  final IdsClient _ids;
  IdsSyncBinding? _idsBinding;
  int _idsGeneration = 0;
  Future<void> _idsWrites = Future.value();
  final _accountWrites = AsyncMutex();

  // Serialize the short persistence/commit phase, never network or captcha waits.
  Future<T> _writeIds<T>(Future<T> Function() action) {
    final result = _idsWrites.then((_) => action());
    _idsWrites = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  IdsSyncBinding? get idsBinding => _idsBinding;
  bool get hasIdsPasskey => _idsBinding?.credential != null;
  bool get usesIdsPasskey => idsAccount?.raw['authMethod'] == 'passkey';
  bool get needsIdsRebind => idsAccount != null && !usesIdsPasskey;
  Iterable<ThirdPartyAccount> get accountsForSync => accounts
      .map(
        (account) =>
            account.platform == ThirdPartyPlatform.ids && account.raw['authMethod'] == 'passkey'
                ? IdsSyncBinding.fromAccount(account)?.toAccount()
                : account,
      )
      .whereType<ThirdPartyAccount>();

  late final SessionTree _tree;
  CampusWebSession? _webSession;
  CampusWebSession get campusWebSession => _webSession ??= CampusWebSession(idsNode, _storage);
  // Stable per-device id, loaded in [initialize]. Stamped onto every locally
  // mutated account so the cloud-sync LWW merge converges.
  String _deviceId = '';

  // Renew status per session-node id (ids/gradescope/hydro/eams/
  // elearning), for the linked-accounts status indicator. Loaded at boot,
  // updated in-memory + persisted on every renew attempt. Local-only.
  final Map<String, RenewStatus> _renewStatuses = {};
  RenewStatus? renewStatus(String nodeId) => _renewStatuses[nodeId];

  ThirdPartyAuthService(this._storage, this._http, {IdsClient? idsClient})
      : _ids = idsClient ?? IdsClient() {
    _tree = SessionTree(
      persist: _persistAccount,
      localAccountRenew: _renewIdsAccount,
      localCanRenew: () => hasIdsPasskey,
      localCookieMint: _ids.mintCookie,
      http: _http,
      baseUrl: () => apiBaseUrl(_storage),
      persistDerived: _persistDerivedCookie,
      recordRenewStatus: _recordRenewStatus,
      persistProbe: _persistProbe,
      persistRenewTimestamp: _persistRenewTimestamp,
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

  /// Convenience: the IDS session node — parent of [eamsNode] and
  /// [elearningNode]. Source of CASTGC / IDS cookies.
  SessionNode get idsNode => _tree.ids;

  /// Convenience: the EAMS downstream node (child of ids).
  SessionNode get eamsNode => _tree.eams;

  /// Convenience: the eLearning downstream node (child of ids).
  SessionNode get elearningNode => _tree.elearning;

  /// Convenience: the egate-app (xshdapp activity check-in) downstream node
  /// (child of ids).
  SessionNode get egateAppNode => _tree.egateApp;
  SessionNode get oaNode => _tree.oa;

  /// Convenience: the Gradescope top-level node.
  SessionNode get gradescopeNode => _tree.gradescope;

  /// Convenience: the Hydro top-level node.
  SessionNode get hydroNode => _tree.hydro;

  List<ThirdPartyPlatform> get boundPlatforms => _accountsSnapshot.map((a) => a.platform).toList();
  Iterable<ThirdPartyAccount> get accounts => _accountsSnapshot;
  ThirdPartyAccount? account(ThirdPartyPlatform p) => _nodeAccount(p);

  List<ThirdPartyAccount> get _accountsSnapshot => [
        _tree.ids.account,
        _tree.gradescope.account,
        _tree.hydro.account,
      ].whereType<ThirdPartyAccount>().toList();

  ThirdPartyAccount? _nodeAccount(ThirdPartyPlatform p) => switch (p) {
        ThirdPartyPlatform.ids => _tree.ids.account,
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
  Future<SyncTombstone> Function(ThirdPartyPlatform platform)? onUnbind;

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
    ThirdPartyAccount? expectedAccount,
  }) async {
    if (updated.platform == ThirdPartyPlatform.ids) {
      await _writeIds(() async {
        if (expectedAccount != null && !identical(_tree.ids.account, expectedAccount)) return;
        if (updated.raw['authMethod'] != 'passkey' ||
            _idsBinding?.credential == null ||
            updated.raw['idsCredentialId'] != _idsBinding!.credential!.credentialId) {
          throw const IdsException('IDS 绑定已变更');
        }
        await _storage.saveThirdPartyAccount(updated);
        _suppressSyncPush = true;
        try {
          _tree.setAccount(updated.platform, updated);
        } finally {
          _suppressSyncPush = false;
        }
      });
      notifyListeners();
      return;
    }
    await _accountWrites.protect(() async {
      if (!identical(_nodeAccount(updated.platform), updated)) return;
      final touched = _touch(updated);
      await _storage.saveThirdPartyAccount(touched);
      if (force) _pendingForcePush = true;
      _tree.setAccount(touched.platform, touched);
    });
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
  ///
  /// Also notifies: a child session's cookie is what a fetch against that
  /// service carries, so a renewal can turn a failing fetch into a working one,
  /// and nothing else would ever say so. Deliberately listeners only, not
  /// [onBindingsChanged] — the cookies are local, and the cloud push has nothing
  /// to gain from them.
  Future<void> _persistDerivedCookie(String nodeId, String? cookie) async {
    final parent = _sessionNode(nodeId)?.parent;
    final owner = parent?.account;
    final epoch = parent?.epoch;
    await _writeIds(() async {
      if (!identical(parent?.account, owner) || parent?.epoch != epoch) return;
      if (cookie == null) {
        await _storage.clearDerivedCookie(nodeId);
      } else {
        await _storage.saveDerivedCookie(nodeId, cookie);
      }
    });
    notifyListeners();
  }

  Future<void> _persistRenewTimestamp(
    String nodeId,
    DateTime? timestamp,
  ) =>
      _storage.saveNextRenewTimestamp(nodeId, timestamp);

  /// Probes update a service's local cookie only. User identity comes from the
  /// authenticated campus profile, never a child's display string.
  Future<void> _persistProbe(String nodeId, KeepaliveResult result) async {
    final cookies = result.cookies;
    if (cookies != null && cookies.isNotEmpty) await _persistDerivedCookie(nodeId, cookies);
  }

  /// Stamp [acc] with this device's id + current time, for LWW merge.
  ThirdPartyAccount _touch(ThirdPartyAccount acc) {
    return acc.copyWith(updatedAt: _nextUpdate(acc.platform, acc.updatedAt), deviceId: _deviceId);
  }

  DateTime _nextUpdate(ThirdPartyPlatform platform, [DateTime? previous]) => nextSyncTimestamp([
        if (previous != null) previous,
        if (_nodeAccount(platform) case final account?) account.updatedAt,
        if (platform == ThirdPartyPlatform.ids && _idsBinding != null) _idsBinding!.updatedAt,
        ..._storage
            .loadThirdPartyTombstones()
            .where((t) => t.platform == platform)
            .map((t) => t.deletedAt),
      ]);

  // -- IDS binding (single source of CASTGC / IDS session) --
  //
  // The ids binding is the ONLY place CASTGC lives in the new
  // architecture. The primary GeekPie SSO session has no tgc/cookies; every
  // campus-system feature (schedule, blackboard, exam, oa-gym, webview
  // features) must read its IDS session through these accessors instead
  // of touching `AuthService.session` fields directly.

  /// True when an IDS binding exists. This is the gate every
  /// CASTGC-dependent feature must check before doing work.
  bool get hasIdsBinding => hasIdsPasskey;

  /// The bound ids account, or null.
  ThirdPartyAccount? get idsAccount => _tree.ids.account;

  /// Cookie string for campus-system requests, always ending with
  /// `CASTGC=<tgc>` when a tgc is present (the form IDS/EAMS expects).
  /// Returns '' when there is no binding or no tgc — callers should treat
  /// that as "session unavailable".
  String idsCookies() => _tree.ids.cookieProvider?.cookies ?? '';

  /// Student id surfaced by the ids binding, or '' if unbound.
  String get idsStudentId => _tree.ids.account?.idsStudentId ?? '';

  /// Hydrate bindings and per-device sessions without network requests.
  Future<void> initialize() async {
    _deviceId = await _storage.ensureDeviceId();
    final loaded = await _storage.loadAllThirdPartyAccounts();
    _idsBinding = IdsSyncBinding.fromAccount(
      loaded.where((a) => a.platform == ThirdPartyPlatform.ids).firstOrNull,
    );
    final deletions = _storage.loadThirdPartyTombstones();
    final idsDeletion = deletions.where((t) => t.platform == ThirdPartyPlatform.ids).firstOrNull;
    if (idsDeletion != null) {
      final deleted = IdsSyncBinding(
        credential: null,
        updatedAt: idsDeletion.deletedAt,
        deviceId: idsDeletion.deviceId,
      );
      _idsBinding = _idsBinding?.merge(deleted) ?? deleted;
    }
    // Seed each node with its persisted account. setAccount routes to the
    // matching node and notifies (boot hydration — the sync hook is not wired
    // yet, so no cloud push fires).
    for (final acc in loaded) {
      final deletion = deletions.where((t) => t.platform == acc.platform).firstOrNull;
      if (deletion != null &&
          (deletion.deletedAt.isAfter(acc.updatedAt) ||
              (deletion.deletedAt == acc.updatedAt &&
                  deletion.deviceId.compareTo(acc.deviceId) >= 0))) {
        await _storage.clearThirdPartyAccount(acc.platform);
        if (acc.platform == ThirdPartyPlatform.ids) await _storage.clearAllDerivedCookies();
        continue;
      }
      _tree.setAccount(acc.platform, acc);
    }
    // Hydrate child node derived cookies so cold start can skip the SSO
    // bounce. These are best-effort — if stale, withCookie's 401 retry will
    // re-mint transparently.
    for (final id in const ['eams', 'elearning', 'egateApp', 'oa']) {
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
    for (final id in _allSessionNodeIds) {
      _sessionNode(id)?.seedNextRenewTimestamp(
        _storage.loadNextRenewTimestamp(id),
      );
    }
    for (final node in [
      _tree.ids,
      _tree.gradescope,
      _tree.hydro,
      _tree.eams,
      _tree.elearning,
      _tree.egateApp,
      _tree.oa,
    ]) {
      if (node.isAvailable && node.nextRenewTimestamp == null) {
        await node.scheduleNextRenew();
      }
    }
    final key = _idsBinding?.credential;
    if (key != null && (!usesIdsPasskey || _tree.ids.account?.account != key.username)) {
      await _setIdsSession(_idsAccount(const {}));
    } else if (key == null && usesIdsPasskey) {
      await _setIdsSession(null);
    }
    _initialized = true;
    notifyListeners();
  }

  /// Look up a [SessionNode] by its stable string id (matches
  /// [ThirdPartyPlatform.id] for top-level nodes, plus 'eams'/'elearning').
  SessionNode? _sessionNode(String nodeId) => switch (nodeId) {
        'ids' => _tree.ids,
        'gradescope' => _tree.gradescope,
        'hydro' => _tree.hydro,
        'eams' => _tree.eams,
        'elearning' => _tree.elearning,
        'egateApp' => _tree.egateApp,
        'oa' => _tree.oa,
        _ => null,
      };

  ThirdPartyAccount _idsAccount(Map<String, dynamic> raw, {String? name}) {
    final account = _idsBinding!.toAccount();
    final previous = idsAccount?.account == account.account ? idsAccount : null;
    return account.copyWith(
      name: name ?? previous?.name,
      email: previous?.email,
      raw: {...raw, ...account.raw},
    );
  }

  Future<ThirdPartyAccount> _renewIdsAccount(ThirdPartyAccount current) async {
    final key = _idsBinding?.credential;
    if (key == null) throw const IdsException('请重新绑定 IDS Passkey', credentialRejected: true);
    final session = await _ids.login(key, backedUp: _storage.idsBackedUpId == key.credentialId);
    if (_idsBinding?.credential?.credentialId != key.credentialId) {
      throw const IdsException('IDS 绑定已变更');
    }
    return _idsAccount(session.raw, name: session.name);
  }

  Future<bool> refreshNode(SessionNode node) async {
    final parent = node.parent;
    final owner = parent?.account;
    final epoch = parent?.epoch;
    if (await node.renew()) return true;
    if (parent != null &&
        parent.isAvailable &&
        (!identical(parent.account, owner) || parent.epoch != epoch)) {
      return node.renew();
    }
    if (node.parent == null || !node.lastRenewWasCredentialError) return false;
    if (!await node.parent!.renew()) return false;
    return node.renew();
  }

  Future<void> _setIdsSession(ThirdPartyAccount? account) async {
    // Invalidate the old owner and every child synchronously. Late CAS/probe
    // results must fail their owner checks before any storage await below.
    _tree.setAccount(ThirdPartyPlatform.ids, account);
    for (final id in const ['eams', 'elearning', 'egateApp', 'oa']) {
      _tree.setDerivedCookie(id, null);
    }
    if (account != null && !_tree.ids.isAvailable) _tree.ids.seedNextRenewTimestamp(DateTime.now());
    for (final id in const ['eams', 'elearning', 'egateApp', 'oa']) {
      await _storage.clearDerivedCookie(id);
    }
    if (account == null) {
      await _storage.clearThirdPartyAccount(ThirdPartyPlatform.ids);
    } else {
      await _storage.saveThirdPartyAccount(account);
    }
  }

  Future<void> markIdsBackedUp(IdsSyncBinding? binding) async {
    final id = binding?.credential?.credentialId;
    if (id != null) await _storage.markIdsBackedUp(id);
  }

  Future<void> applyIdsSyncBinding(IdsSyncBinding? binding) async {
    if (binding == null) return;
    var changed = false;
    await _writeIds(() async {
      // Network results are snapshots. Reconcile against the state *now*, after
      // any local bind/unbind that happened while the request was in flight.
      final next = _idsBinding?.merge(binding) ?? binding;
      if (jsonEncode(_idsBinding?.toJson()) == jsonEncode(next.toJson())) return;
      final previous = _idsBinding?.credential?.credentialId;
      final replacesKey = next.credential == null || previous != next.credential?.credentialId;
      if (replacesKey) _idsGeneration++;
      _idsBinding = next;
      if (replacesKey) await _storage.clearIdsCandidate();
      _suppressSyncPush = true;
      try {
        if (replacesKey) {
          final key = next.credential;
          if (key != null) {
            await _setIdsSession(_idsAccount(const {}));
          } else if (usesIdsPasskey) {
            await _setIdsSession(null);
          }
        } else if (next.credential != null && idsAccount != null) {
          final account = _idsAccount(idsAccount!.raw);
          await _storage.saveThirdPartyAccount(account);
          _tree.setAccount(ThirdPartyPlatform.ids, account);
        }
      } finally {
        _suppressSyncPush = false;
      }
      changed = true;
    });
    if (changed) notifyListeners();
  }

  Future<ThirdPartyAccount> bindIds({
    required String account,
    required String password,
    required IdsCaptchaPrompt promptCaptcha,
    bool Function()? isCancelled,
  }) async {
    final generation = ++_idsGeneration;
    void ensureCurrent() {
      if (generation != _idsGeneration || isCancelled?.call() == true) {
        throw const IdsException('IDS 绑定操作已取消或被替换');
      }
    }

    IdsPasskey? key;
    IdsSession? session;
    final pending = await _writeIds(() async {
      ensureCurrent();
      return _storage.loadIdsCandidate();
    });
    if (pending?.account == account) {
      try {
        session = await _ids.login(pending!.credential);
        ensureCurrent();
        key = pending.credential;
      } on IdsException catch (error) {
        if (!error.credentialRejected) rethrow;
        await _writeIds(() async {
          ensureCurrent();
          await _storage.clearIdsCandidate();
        });
      }
    }
    if (key == null) {
      final registered = await _ids.register(
        account,
        password,
        promptCaptcha: promptCaptcha,
        saveCandidate: (credential) => _writeIds(() async {
          ensureCurrent();
          await _storage.saveIdsCandidate(account, credential);
          ensureCurrent();
        }),
      );
      ensureCurrent();
      key = registered.credential;
      session = registered.session;
    }
    final credential = key;
    final bound = await _writeIds(() async {
      ensureCurrent();
      _idsBinding = IdsSyncBinding(
        credential: credential,
        updatedAt: _nextUpdate(ThirdPartyPlatform.ids),
        deviceId: _deviceId,
      );
      _suppressSyncPush = true;
      final account = _idsAccount(session!.raw, name: session.name);
      try {
        await _setIdsSession(account);
      } finally {
        _suppressSyncPush = false;
      }
      await _storage.clearIdsCandidate();
      return account;
    });
    ensureCurrent();
    _onTreeChanged(force: true);
    return bound;
  }

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
    if (platform == ThirdPartyPlatform.ids) {
      throw ThirdPartyBindException(platform, '请使用 IDS Passkey 绑定校园账号');
    }
    final body = <String, dynamic>{
      'account': account,
      'password': password,
    };
    if (platform == ThirdPartyPlatform.hydro && hydroOrigin != null && hydroOrigin.isNotEmpty) {
      body['args'] = {'url': hydroOrigin};
    }

    final route = platform.id;
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

  Future<bool> unbindIdsWithRemote({required IdsVerificationPrompt promptVerification}) async {
    final key = _idsBinding?.credential;
    // Local removal and sync tombstones commit independently of school access.
    // Keep only this operation's key in memory until its remote attempt ends.
    await unbind(ThirdPartyPlatform.ids);
    if (key == null) return false;
    try {
      await _ids.revoke(key, promptVerification: promptVerification);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> unbind(ThirdPartyPlatform platform) async {
    if (platform == ThirdPartyPlatform.ids) {
      ++_idsGeneration;
      await _writeIds(() async {
        final deletion = await onUnbind?.call(ThirdPartyPlatform.ids);
        _idsBinding = IdsSyncBinding(
          credential: null,
          updatedAt: deletion?.deletedAt ?? DateTime.now(),
          deviceId: deletion?.deviceId ?? _deviceId,
        );
        await _storage.clearIdsCandidate();
        _suppressSyncPush = true;
        try {
          await _setIdsSession(null);
        } finally {
          _suppressSyncPush = false;
        }
      });
      _onTreeChanged(force: true);
      return;
    }
    await onUnbind?.call(platform);
    _tree.setAccount(platform, null);
    await _storage.clearThirdPartyAccount(platform);
    // Record a tombstone for the cloud-sync merge so this deletion is not
    // resurrected by an older remote copy on the next pull.
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
    for (final id in const ['eams', 'elearning', 'egateApp', 'oa']) {
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
  ) =>
      _accountWrites.protect(() async {
        _suppressSyncPush = true;
        try {
          final byPlatform = {
            for (final a in kept) a.platform: a,
          };
          for (final p in ThirdPartyPlatform.values) {
            // IDS is merged separately from local sessions.
            if (p == ThirdPartyPlatform.ids) continue;
            final next = byPlatform[p];
            final cur = _nodeAccount(p);
            // Skip no-op writes: if the merged account equals the current one
            // (same token, same updatedAt), don't touch storage or fire notifies.
            if (next != null && cur != null && _accountEqual(cur, next)) continue;
            if (next == null && cur == null) continue;
            if (next != null) {
              _tree.setAccount(p, next);
              await _storage.saveThirdPartyAccount(next);
            } else {
              _tree.setAccount(p, null);
              await _storage.clearThirdPartyAccount(p);
            }
          }
        } finally {
          _suppressSyncPush = false;
        }
        // One notification for the whole merge — through the funnel, so the same
        // downstream effects a manual binding change gets happen for a merge too.
        // It used to notify listeners only, which left everything wired to
        // onBindingsChanged (the cloud push, and the services that refetch when a
        // binding appears) blind to a merge that replaced the account.
        _onTreeChanged();
      });

  /// Cheap structural equality used by [applySyncMerge] to skip no-op writes.
  static bool _accountEqual(ThirdPartyAccount a, ThirdPartyAccount b) {
    return a.token == b.token &&
        a.account == b.account &&
        a.expire == b.expire &&
        a.updatedAt == b.updatedAt &&
        a.deviceId == b.deviceId;
  }

  /// Update the raw data of a bound account (e.g. after IDS session renewal).
  Future<void> updateRaw(
    ThirdPartyPlatform platform,
    Map<String, dynamic> newRaw,
  ) async {
    final acc = _nodeAccount(platform);
    if (acc == null) return;
    if (platform == ThirdPartyPlatform.ids) {
      final raw = {
        ...newRaw,
        'authMethod': acc.raw['authMethod'],
        'idsCredentialId': acc.raw['idsCredentialId'],
        'credential': acc.raw['credential'],
      };
      await _persistAccount(acc.copyWith(raw: raw), expectedAccount: acc);
      return;
    }
    final touched = _touch(acc.copyWith(raw: newRaw));
    await _storage.saveThirdPartyAccount(touched);
    _tree.setAccount(platform, touched);
  }

  Future<void> applyLegacyCampusSync(ThirdPartyAccount? incoming, SyncTombstone? deletion) async {
    if (incoming == null && deletion == null) return;
    var changed = false;
    await _writeIds(() async {
      if (hasIdsPasskey) return;
      final current = idsAccount;
      if (incoming != null && current == null && _idsBinding != null) {
        final time = incoming.updatedAt.compareTo(_idsBinding!.updatedAt);
        if (time < 0 || (time == 0 && incoming.deviceId.compareTo(_idsBinding!.deviceId) < 0)) {
          return;
        }
      }
      if (incoming != null && current != null && incoming.compareVersionTo(current) <= 0) return;
      if (incoming == null && current != null && deletion != null) {
        final time = deletion.deletedAt.compareTo(current.updatedAt);
        if (time < 0 || (time == 0 && deletion.deviceId.compareTo(current.deviceId) < 0)) return;
      }
      if (incoming != null && incoming.raw['authMethod'] == 'passkey') return;
      if (incoming == null && current == null) return;
      if (current?.account != incoming?.account || current?.boundAt != incoming?.boundAt) {
        ++_idsGeneration;
      }
      if (incoming == null && deletion != null) {
        _idsBinding = IdsSyncBinding(
          credential: null,
          updatedAt: deletion.deletedAt,
          deviceId: deletion.deviceId,
        );
      }
      _suppressSyncPush = true;
      try {
        await _setIdsSession(incoming);
      } finally {
        _suppressSyncPush = false;
      }
      changed = true;
    });
    if (changed) notifyListeners();
  }

  /// Renew nodes whose persisted [SessionNode.nextRenewTimestamp] is due.
  /// Top-level password nodes still require auto-renew credentials; derived
  /// nodes can renew independently from their parent while their cookie is
  /// still usable.
  Future<List<ThirdPartyPlatform>> autoRenewIfNeeded() async {
    final failed = <ThirdPartyPlatform>[];
    final nodes = [
      _tree.ids,
      _tree.gradescope,
      _tree.hydro,
      _tree.eams,
      _tree.elearning,
      _tree.egateApp,
      _tree.oa,
    ];
    for (final node in nodes) {
      if (node.id == 'oa' && !usesIdsPasskey) continue;
      if (!node.isRenewDue) continue;
      final ok = await node.renewIfDue();
      if (!ok && node.parent == null && node.canRenew) {
        failed.add(ThirdPartyPlatform.fromId(node.id)!);
      }
    }
    return failed;
  }

  Future<void> clearAll() async {
    ++_idsGeneration;
    await _writeIds(() async {
      _suppressSyncPush = true;
      try {
        if (hasIdsPasskey || idsAccount != null) {
          _idsBinding =
              IdsSyncBinding(credential: null, updatedAt: DateTime.now(), deviceId: _deviceId);
        }
        final unbindHook = onUnbind;
        for (final p in ThirdPartyPlatform.values) {
          if (_nodeAccount(p) != null) {
            final deletion = await unbindHook?.call(p);
            if (p == ThirdPartyPlatform.ids && deletion != null) {
              _idsBinding = IdsSyncBinding(
                credential: null,
                updatedAt: deletion.deletedAt,
                deviceId: deletion.deviceId,
              );
            }
          }
          _tree.setAccount(p, null);
        }
        for (final id in const ['eams', 'elearning', 'egateApp', 'oa']) {
          _tree.setDerivedCookie(id, null);
        }
        await _storage.clearIdsCandidate();
        await _storage.clearAllThirdPartyAccounts();
        await _storage.clearAllDerivedCookies();
      } finally {
        _suppressSyncPush = false;
      }
    });
    _onTreeChanged(force: true);
  }

  @override
  void dispose() {
    _webSession?.dispose();
    _tree.removeListener(_onTreeChanged);
    _tree.dispose();
    super.dispose();
  }
}
