import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/campus_card/core/async_mutex.dart';
import '../models/ecard_sync_binding.dart';
import '../models/third_party_account.dart';
import 'auth_service.dart';
import 'debug_logger.dart';
import 'storage_service.dart';
import 'sync_crypto.dart';
import 'sync_envelope.dart';
import 'third_party_auth_service.dart';

/// Thrown by [SyncService.pull] when the cloud has a sync blob but this device
/// has no cached master key — the caller must prompt for the master password
/// and call [restoreWithMasterPassword].
class NeedMasterPassword implements Exception {
  @override
  String toString() => 'Cloud sync needs the master password to decrypt';
}

/// Result of a setup/restore attempt carrying whether a fresh master password
/// was needed and a human-readable message.
class SyncOutcome {
  final bool ok;
  final String message;
  final bool needMasterPassword;
  const SyncOutcome({
    required this.ok,
    required this.message,
    this.needMasterPassword = false,
  });
}

/// Outcome of a single Casdoor write call. Casdoor returns HTTP 200 for ALL
/// outcomes (even authz denials — the `WriteHeader(403)` is commented out in
/// `routers/base.go`), so [ok] is decided by the JSON body's `status` field,
/// NOT the HTTP status. [msg] carries Casdoor's error message (e.g.
/// "Unauthorized operation", "Access token has expired") so the UI can surface
/// the real reason instead of a generic "写入失败".
class SyncCasdoorResult {
  final bool ok;
  final int? httpStatus;
  final String? msg;
  const SyncCasdoorResult(this.ok, {this.httpStatus, this.msg});

  String describe(String shortLabel) {
    if (ok) return shortLabel;
    final m = msg;
    return m == null || m.isEmpty ? '$shortLabel (HTTP ${httpStatus ?? "?"})' : '$shortLabel: $m';
  }
}

/// End-to-end-encrypted cloud sync of third-party account bindings.
///
/// Storage backend is Casdoor itself: the encrypted blob lives in the signed-in
/// user's `User.properties["techpie_sync"]` field, written via Casdoor's
/// self-service `POST /api/update-user?id=<owner>/<name>&columns=properties`
/// using the user's own OAuth access token (the same `geekpieToken` used for
/// TechPie auth). The TechPie Node backend is not involved in sync at all.
///
/// The blob is AES-256-GCM encrypted with a key derived (PBKDF2, 200k iters)
/// from a user-chosen master password. The server only ever sees ciphertext.
/// Each device caches the derived key in secure storage so it does not need to
/// re-prompt on every push; a new device restores by entering the password once.
class SyncService extends ChangeNotifier {
  /// Casdoor base URL. Hardcoded (mirrors [UniAuthService] config) — sync talks
  /// to Casdoor directly, never to the TechPie backend, so it does NOT use
  /// [apiBaseUrl] / the localhost toggle.
  static const String _casdoorBaseUrl = 'https://auth.geekpie.club';
  static const String _blobKey = 'techpie_sync';
  static const String _columnsQuery = 'columns=properties';

  final AuthService _auth;
  final ThirdPartyAuthService _tpAuth;
  final StorageService _storage;
  final http.Client _client;
  final EcardSyncStore? _ecard;
  final DebugLogger? _logger;
  CachedSyncKey? _cachedKey;
  bool _needsRestore = false;
  DateTime? _lastSyncAt;
  String? _lastError;
  // Stable per-device id, loaded once at boot and stamped onto every
  // locally-touched account / tombstone so the LWW merge converges.
  String _deviceId = '';
  // Latest per-platform deletion versions survive restart and successful
  // uploads, so a late old cloud copy cannot resurrect an unbound account.
  final List<SyncTombstone> _tombstones = [];
  final _operations = AsyncMutex();
  bool _applyingRemote = false;

  SyncService(
    this._auth,
    this._tpAuth,
    this._storage, {
    http.Client? client,
    EcardSyncStore? ecard,
    DebugLogger? logger,
  })  : _ecard = ecard,
        _client = client ?? http.Client(),
        _logger = logger {
    _tombstones.addAll(_storage.loadThirdPartyTombstones());
  }

  bool get enabled => _storage.syncEnabled;
  bool get hasLocalKey => _cachedKey != null;
  bool get needsRestore => _needsRestore;
  DateTime? get lastSyncAt => _lastSyncAt;

  /// The most recent local mutation across all bindings (bind/rebind/renew),
  /// for comparison against [cloudLastModified] in the sync settings UI.
  /// Null when there are no local bindings at all.
  DateTime? get localLastModified {
    final times = [
      ..._tpAuth.accountsForSync.map((a) => a.updatedAt),
      ..._tombstones.map((t) => t.deletedAt),
    ];
    if (times.isEmpty) return null;
    return times.reduce(
      (a, b) => a.isAfter(b) ? a : b,
    );
  }

  /// Best-effort read of the cloud blob's most recent modification time,
  /// without merging or writing anything back — just for the "local vs
  /// cloud version" comparison in the sync settings UI. Returns null if
  /// there's no cloud blob, or this device has no cached key to decrypt it
  /// (surface as "cloud version unknown" rather than attempting a merge).
  Future<DateTime?> cloudLastModified() async {
    if (_cachedKey == null) return null;
    final blob = await _readBlob();
    if (blob == null) return null;
    final dot = blob.indexOf('.');
    if (dot <= 0) return null;
    final inner = blob.substring(dot + 1);
    final plain = await SyncCrypto.decrypt(inner, _cachedKey!.key);
    if (plain == null) return null;
    final remote = SyncEnvelope.decode(plain);
    if (remote == null) return null;
    final times = [
      ...remote.accounts.map((a) => a.updatedAt),
      ...remote.tombstones.map((t) => t.deletedAt),
    ];
    if (times.isEmpty) return null;
    return times.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Human-readable text from the most recent failed Casdoor call (for the
  /// "立即备份/恢复" toasts). Null when the last call succeeded.
  String? get lastError => _lastError;

  /// Load the cached derived key (if any) from secure storage and the stable
  /// device id from SharedPreferences. Call at boot.
  Future<void> loadCachedKey() async {
    final s = await _storage.loadSyncMasterKey();
    _cachedKey = await CachedSyncKey.fromStorageString(s);
    final iso = _storage.syncLastAt;
    _lastSyncAt = iso == null ? null : DateTime.tryParse(iso);
    _deviceId = await _storage.ensureDeviceId();
    notifyListeners();
  }

  /// Persist [key] to secure storage + memory.
  Future<void> _cacheKey(CachedSyncKey key) async {
    _cachedKey = key;
    await _storage.saveSyncMasterKey(await key.toStorageString());
  }

  Future<void> _clearCachedKey() async {
    _cachedKey = null;
    await _storage.clearSyncMasterKey();
  }

  void _debugLog(String s) {
    // Sync HTTP traffic deliberately bypasses LoggingHttpClient (the blob and
    // the bearer stay out of the request log), so this is the only client-side
    // trace of what Casdoor answered. It goes to the console *and* to the app's
    // own log, so a device that cannot be attached to a terminal can still be
    // read: settings → Developer → Debug mode → View Logs.
    if (kDebugMode) debugPrint('[sync] $s');
    _logger?.log(
      method: 'SYNC',
      url: 'auth.geekpie.club',
      tag: 'Sync',
      responseBody: DebugLogger.redactSensitive(s),
    );
  }

  // -- Casdoor HTTP -------------------------------------------------------------

  String? _token() => _auth.session?.geekpieToken;

  Future<String?> _requireToken() async {
    final token = _token();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=UTF-8',
      };

  /// Fetch the signed-in user's full Casdoor user object (the `data` field of
  /// the get-account response). Returns null on transport failure.
  Future<Map<String, dynamic>?> _getAccount(String token) async {
    http.Response resp;
    try {
      resp = await _client.get(
        Uri.parse('$_casdoorBaseUrl/api/get-account'),
        headers: _authHeaders(token),
      );
    } catch (e) {
      _debugLog('get-account transport error: $e');
      return null;
    }
    if (resp.statusCode != 200) {
      _debugLog('get-account HTTP ${resp.statusCode}: ${resp.body}');
      return null;
    }
    try {
      final account = jsonDecode(resp.body) as Map<String, dynamic>;
      if (account['status'] != null && account['status'] != 'ok') {
        _debugLog('get-account rejected');
        return null;
      }
      return account;
    } catch (e) {
      _debugLog('get-account JSON decode error: $e');
      return null;
    }
  }

  /// POST a user object to `/api/update-user`, persisting only the `properties`
  /// column. [body] should be a *minimal* object carrying `owner`, `name`, and
  /// `properties` — NOT the full get-account echo (avoids re-sending password /
  /// accessToken / roles / groups). Pass [id] = `<owner>/<name>` so Casbin's
  /// object-identity resolution is unambiguous (it prefers the `id` query param
  /// over body parsing).
  Future<SyncCasdoorResult> _putAccount(
    String token,
    Map<String, dynamic> body,
    String id,
  ) async {
    final uri = Uri.parse(
      '$_casdoorBaseUrl/api/update-user'
      '?id=${Uri.encodeQueryComponent(id)}&$_columnsQuery',
    );
    http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: _authHeaders(token),
        body: jsonEncode(body),
      );
    } catch (e) {
      _debugLog('update-user transport error: $e');
      return SyncCasdoorResult(false, msg: '网络错误: $e');
    }

    // Casdoor returns 200 even on authz denial, but a real 401 means the token
    // is gone — try one refresh + retry before giving up.
    if (resp.statusCode == 401) {
      // The 401 is proof the token is refused, so this renewal does not
      // second-guess it against the stored expiry.
      if (await _auth.tryRenewSession(force: true)) {
        final t2 = _token();
        if (t2 == null || t2.isEmpty) {
          return const SyncCasdoorResult(false, httpStatus: 401, msg: '登录已过期，请重新登录');
        }
        try {
          resp = await _client.post(
            uri,
            headers: _authHeaders(t2),
            body: jsonEncode(body),
          );
        } catch (e) {
          return SyncCasdoorResult(false, msg: '网络错误: $e');
        }
      } else {
        return const SyncCasdoorResult(false, httpStatus: 401, msg: '登录已过期，请重新登录');
      }
    }

    dynamic decoded;
    try {
      decoded = resp.body.isEmpty ? null : jsonDecode(resp.body);
    } catch (_) {
      final snippet = resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body;
      _debugLog('update-user non-JSON HTTP ${resp.statusCode}: $snippet');
      return SyncCasdoorResult(false, httpStatus: resp.statusCode, msg: '响应非 JSON');
    }

    final statusOk = decoded is Map && decoded['status'] == 'ok';
    final dataStr = decoded is Map ? decoded['data']?.toString() : null;
    final msgStr = decoded is Map ? decoded['msg']?.toString() : null;
    // data="Unaffected" is still success (no-op write). Only status!="ok" is failure.
    if (!statusOk) {
      _debugLog('update-user denied: HTTP ${resp.statusCode} msg=$msgStr body=${resp.body}');
      return SyncCasdoorResult(false, httpStatus: resp.statusCode, msg: msgStr);
    }
    _debugLog('update-user ok: HTTP ${resp.statusCode} data=$dataStr');
    return SyncCasdoorResult(true, httpStatus: resp.statusCode, msg: dataStr);
  }

  // -- Blob access --------------------------------------------------------------

  /// Read the encrypted blob from the user's properties, or null if absent.
  Future<String?> _readBlob({bool requireReadableAccount = false}) async {
    final token = await _requireToken();
    if (token == null) {
      if (requireReadableAccount) throw StateError('未登录主账号');
      return null;
    }
    final account = await _getAccount(token);
    if (account == null) {
      if (requireReadableAccount) throw StateError('无法读取云端同步状态');
      return null;
    }
    final props =
        account['data'] is Map ? (account['data'] as Map)['properties'] : account['properties'];
    if (props is! Map) return null;
    final v = props[_blobKey];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// Resolve the user's `(owner, name)` identity from a get-account response.
  ///
  /// Casdoor's `GetAccount` sets `Sub = user.Id` (= `"<owner>/<name>"`) and
  /// `Data = <masked user>` (which also carries `owner`/`name`/`id`). Different
  /// Casdoor versions / masking configs populate these inconsistently, so we
  /// try several sources in order of reliability and return the first that
  /// yields both a non-empty owner and name:
  ///   1. top-level `sub`           (= user.Id, always set by GetAccount)
  ///   2. `data.id`                 (= user.Id)
  ///   3. `data.owner` + `data.name` (the split fields)
  ///   4. top-level `name` + `data.owner`
  /// `owner`/`name` are the user's EXISTING Casdoor identity — there is nothing
  /// to "create"; if all sources are empty the token isn't actually
  /// authenticated and the caller should re-login.
  ({String owner, String name})? _resolveOwnerName(Map<String, dynamic> account) {
    String? splitOwner(String id) {
      if (id.isEmpty) return null;
      final idx = id.indexOf('/');
      return idx > 0 ? id.substring(0, idx) : (id.isNotEmpty ? id : null);
    }

    String? splitName(String id) {
      if (id.isEmpty) return null;
      final idx = id.indexOf('/');
      return idx >= 0 && idx < id.length - 1 ? id.substring(idx + 1) : null;
    }

    final data = account['data'] is Map ? account['data'] as Map : null;

    // 1. top-level sub
    final sub = account['sub']?.toString() ?? '';
    if (sub.isNotEmpty) {
      final o = splitOwner(sub), n = splitName(sub);
      if (o != null && n != null && o.isNotEmpty && n.isNotEmpty) {
        return (owner: o, name: n);
      }
    }
    // 2. data.id
    if (data != null) {
      final id = data['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        final o = splitOwner(id), n = splitName(id);
        if (o != null && n != null && o.isNotEmpty && n.isNotEmpty) {
          return (owner: o, name: n);
        }
      }
    }
    // 3. data.owner + data.name
    if (data != null) {
      final o = data['owner']?.toString() ?? '';
      final n = data['name']?.toString() ?? '';
      if (o.isNotEmpty && n.isNotEmpty) {
        return (owner: o, name: n);
      }
    }
    // 4. top-level name + data.owner
    if (data != null) {
      final o = data['owner']?.toString() ?? '';
      final n = account['name']?.toString() ?? '';
      if (o.isNotEmpty && n.isNotEmpty) {
        return (owner: o, name: n);
      }
    }
    return null;
  }

  /// Write the encrypted blob (or clear it if [blob] is null) to properties.
  /// Builds a MINIMAL body `{owner, name, properties}` so we never echo
  /// password/accessToken/roles/groups back to Casdoor; passes `id=<owner>/<name>`
  /// so Casbin self-update authz matches cleanly.
  Future<SyncCasdoorResult> _writeBlob(String? blob) async {
    final token = await _requireToken();
    if (token == null) {
      return const SyncCasdoorResult(false, msg: '未登录主账号');
    }
    final account = await _getAccount(token);
    if (account == null) {
      return const SyncCasdoorResult(false, msg: '无法读取云端账号');
    }
    final id = _resolveOwnerName(account);
    if (id == null) {
      // Log the actual response shape so we can see where owner/name live.
      final keys = account.keys.toList();
      final dataKeys = account['data'] is Map
          ? (account['data'] as Map).keys.toList()
          : '<not a map: ${account['data'].runtimeType}>';
      _debugLog(
        'get-account missing owner/name. top-level keys=$keys; '
        'sub=${account['sub']}; name=${account['name']}; '
        'data keys=$dataKeys',
      );
      return const SyncCasdoorResult(
        false,
        msg: '无法解析云端账号身份，请重新登录主账号',
      );
    }
    final user =
        (account['data'] is Map ? (account['data'] as Map) : account) as Map<String, dynamic>;
    final props = (user['properties'] as Map?)?.cast<String, String>() ?? <String, String>{};
    final updated = Map<String, String>.from(props);
    if (blob == null) {
      updated.remove(_blobKey);
    } else {
      updated[_blobKey] = blob;
    }
    final body = <String, dynamic>{
      'owner': id.owner,
      'name': id.name,
      'properties': updated,
    };
    return _putAccount(token, body, '${id.owner}/${id.name}');
  }

  // -- Public API ---------------------------------------------------------------

  /// True if the cloud user has a sync blob (i.e. another device set up sync).
  /// Does not decrypt — just checks presence. Cheap probe for the UI.
  Future<bool> cloudHasBlob() async => (await _readBlob()) != null;

  /// Serialize the current local bindings + retained tombstones into the
  /// envelope plaintext. Accounts are stamped with this device's id and a
  /// fresh [updatedAt] only via [touchLocal]; already-stamped accounts pass
  /// through unchanged.
  Future<String> _serializeEnvelope() async {
    final env = SyncEnvelope.fromLocal(
      ecard: await _ecard?.readSyncBinding(),
      accounts: _tpAuth.accountsForSync,
      tombstones: _tombstones,
    );
    return env.encode();
  }

  /// Stamp [acc] with this device's id and the current wall clock, producing
  /// a new [ThirdPartyAccount] that wins LWW against any older copy. Called
  /// by [ThirdPartyAuthService] mutation paths via the public [touchLocal].
  ThirdPartyAccount touchLocal(ThirdPartyAccount acc) {
    return acc.copyWith(
      updatedAt: nextSyncTimestamp([acc.updatedAt]),
      deviceId: _deviceId,
    );
  }

  /// Record that [platform] was deliberately unbound on this device. The
  /// tombstone is carried in the next push and participates in LWW merge so a
  /// remote account older than this deletion is not resurrected on pull.
  Future<SyncTombstone> recordTombstone(ThirdPartyPlatform platform) async {
    final deviceId = await _storage.ensureDeviceId();
    final now = nextSyncTimestamp([
      ..._tpAuth.accountsForSync.where((a) => a.platform == platform).map((a) => a.updatedAt),
      ..._tombstones.where((t) => t.platform == platform).map((t) => t.deletedAt),
    ]);
    final tombstone = SyncTombstone(platform: platform, deletedAt: now, deviceId: deviceId);
    // Replace any existing tombstone for the same platform (keep newest).
    _tombstones.removeWhere((t) => t.platform == platform);
    _tombstones.add(tombstone);
    await _storage.saveThirdPartyTombstones(_tombstones);
    return tombstone;
  }

  Future<void> _mergeTombstones(List<SyncTombstone> incoming) async {
    for (final tomb in incoming) {
      final current = _tombstones.where((t) => t.platform == tomb.platform).firstOrNull;
      if (current != null && current.compareVersionTo(tomb) >= 0) continue;
      _tombstones.removeWhere((t) => t.platform == tomb.platform);
      _tombstones.add(tomb);
    }
    await _storage.saveThirdPartyTombstones(_tombstones);
  }

  /// Push current local bindings to the cloud (encrypted). Requires a cached
  /// key (i.e. the device has already been set up / restored). Returns a result
  /// whose [msg] carries Casdoor's error text on failure. On success pending
  /// deletion versions remain local as well as in the cloud blob.
  Future<SyncCasdoorResult>? _pushInFlight;
  bool _pushPending = false;

  Future<SyncCasdoorResult> push() {
    final current = _pushInFlight;
    if (current != null) {
      _pushPending = true;
      return current;
    }
    final pending = _operations.protect(_drainPushes).whenComplete(() => _pushInFlight = null);
    _pushInFlight = pending;
    return pending;
  }

  Future<SyncCasdoorResult> _drainPushes() async {
    late SyncCasdoorResult result;
    do {
      _pushPending = false;
      result = await _pushOnce();
    } while (_pushPending);
    return result;
  }

  Future<SyncCasdoorResult> _pushOnce() async {
    if (!enabled || _cachedKey == null) {
      return const SyncCasdoorResult(false, msg: '云同步未开启或缺少主密码');
    }
    var payload = await _serializeEnvelope();
    // Read-modify-write against the copy in the cloud: this device may be behind
    // it (a newer eCard edit or deletion, or a field a newer build wrote), and a
    // blind push would delete what this device has never seen.
    try {
      final remoteBlob = await _readBlob(requireReadableAccount: true);
      if (remoteBlob != null) {
        final dot = remoteBlob.indexOf('.');
        final plain = dot < 0
            ? null
            : await SyncCrypto.decrypt(remoteBlob.substring(dot + 1), _cachedKey!.key);
        final remote = plain == null ? null : SyncEnvelope.decode(plain);
        if (remote == null) throw StateError('无法解密云端同步状态，请先恢复云同步');
        final local = SyncEnvelope.decode(payload)!;
        final merged = local.mergeWith(remote);
        payload = SyncEnvelope(
          v: local.v,
          accounts: merged.accounts,
          tombstones: merged.tombstones,
          // Without an eCard store this build has no opinion on the binding, so
          // the cloud's copy is the one that stands.
          ecard: _ecard == null ? remote.ecard : (local.ecard?.merge(remote.ecard) ?? remote.ecard),
          unknown: remote.unknown,
        ).encode();
      }
    } catch (_) {
      _lastError = '无法核对云端备份，请先恢复或重试云同步';
      notifyListeners();
      return SyncCasdoorResult(false, msg: _lastError);
    }
    // Reuse the cached salt so other devices' cached keys keep working.
    final salted = base64.encode(_cachedKey!.salt);
    final inner = await SyncCrypto.encrypt(payload, _cachedKey!.key);
    final blob = '$salted.$inner';
    final res = await _writeBlob(blob);
    _lastError = res.ok ? null : res.msg;
    if (res.ok) {
      final uploaded = SyncEnvelope.decode(payload)!;
      await _mergeTombstones(uploaded.tombstones);
      await _tpAuth.markIdsBackedUp(uploaded.ids);
      await _applyCampusSync(uploaded);
      _lastSyncAt = DateTime.now();
      await _storage.setSyncLastAt(_lastSyncAt!.toIso8601String());
      notifyListeners();
    }
    return res;
  }

  /// Pull the cloud blob and merge it with the local state using per-platform
  /// last-writer-wins (with [deviceId] tie-break and tombstones for
  /// deletions). Unlike a blind overwrite, a local binding newer than the
  /// cloud copy is preserved, and a cloud deletion (tombstone) newer than a
  /// local binding removes it locally. Throws [NeedMasterPassword] if no key
  /// is cached on this device.
  Future<void> pull() => _operations.protect(_pull);

  Future<void> _pull() async {
    if (!enabled) return;
    final blob = await _readBlob();
    if (blob == null) return;
    if (_cachedKey == null) {
      _needsRestore = true;
      notifyListeners();
      throw NeedMasterPassword();
    }
    final dot = blob.indexOf('.');
    if (dot <= 0) return;
    final inner = blob.substring(dot + 1);
    final plain = await SyncCrypto.decrypt(inner, _cachedKey!.key);
    if (plain == null) {
      // Cached key no longer matches the cloud blob (master password was
      // changed on another device). Force re-entry.
      _needsRestore = true;
      await _clearCachedKey();
      notifyListeners();
      throw NeedMasterPassword();
    }
    final remote = SyncEnvelope.decode(plain);
    if (remote == null) return;
    final local = SyncEnvelope.fromLocal(
      ecard: await _ecard?.readSyncBinding(),
      accounts: _tpAuth.accountsForSync,
      tombstones: _tombstones,
    );
    final merged = local.mergeWith(remote);
    await _applyRemoteState(merged, remote);
    _lastSyncAt = DateTime.now();
    await _storage.setSyncLastAt(_lastSyncAt!.toIso8601String());
    _needsRestore = false;
    // Already inside the sync operation queue; do not enqueue a nested push.
    if (!_envelopeEquals(remote, merged)) await _pushOnce();
    notifyListeners();
  }

  Future<void> _applyRemoteState(SyncEnvelope merged, SyncEnvelope remote) async {
    _applyingRemote = true;
    try {
      await _mergeTombstones(merged.tombstones);
      // Apply the merged account set locally. applySyncMerge does NOT record
      // tombstones (the merge already accounted for them); it just writes the
      // winning account per platform and clears platforms whose tombstone won.
      final removed = ThirdPartyPlatform.values
          .where(
            (p) => !merged.accounts.any((a) => a.platform == p),
          )
          .toSet();
      await _tpAuth.applySyncMerge(merged.accounts, removed);
      await _tpAuth.markIdsBackedUp(remote.ids);
      await _applyCampusSync(merged);
      await _ecard?.applySyncBinding(merged.ecard);
    } finally {
      _applyingRemote = false;
    }
  }

  /// Cheap structural equality between two envelopes — enough to decide
  /// whether a pull changed anything worth pushing back. Compares the
  /// encoded form; envelope encode is deterministic.
  bool _envelopeEquals(SyncEnvelope a, SyncEnvelope b) {
    if (jsonEncode(a.ecard?.toJson()) != jsonEncode(b.ecard?.toJson())) return false;
    if (jsonEncode(a.unknown) != jsonEncode(b.unknown)) return false;
    if (a.accounts.length != b.accounts.length) return false;
    if (a.tombstones.length != b.tombstones.length) return false;
    // Account order is platform-stable within an envelope.
    for (var i = 0; i < a.accounts.length; i++) {
      final ax = a.accounts[i], bx = b.accounts[i];
      if (ax.platform != bx.platform) return false;
      if (ax.token != bx.token ||
          ax.account != bx.account ||
          ax.updatedAt != bx.updatedAt ||
          ax.deviceId != bx.deviceId) {
        return false;
      }
    }
    for (var i = 0; i < a.tombstones.length; i++) {
      final ta = a.tombstones[i], tb = b.tombstones[i];
      if (ta.platform != tb.platform ||
          ta.deletedAt != tb.deletedAt ||
          ta.deviceId != tb.deviceId) {
        return false;
      }
    }
    return true;
  }

  Future<void> _applyCampusSync(SyncEnvelope envelope) async {
    await _tpAuth.applyIdsSyncBinding(envelope.ids);
    await _tpAuth.applyLegacyCampusSync(
      envelope.accounts.where((a) => a.platform == ThirdPartyPlatform.ids).firstOrNull,
      envelope.tombstones.where((t) => t.platform == ThirdPartyPlatform.ids).firstOrNull,
    );
  }

  /// First-time setup on a device that is not syncing yet: derive a key from
  /// [password] (fresh salt), cache it, and push current bindings.
  ///
  /// When the cloud already holds a backup — typically another device's — the
  /// caller confirms the overwrite and passes [overwriteRemote]. Without that
  /// confirmation the call refuses, so a thin local state cannot silently
  /// replace a good backup.
  Future<SyncOutcome> setupWithMasterPassword(
    String password, {
    bool overwriteRemote = false,
  }) async {
    if (password.isEmpty) {
      return const SyncOutcome(ok: false, message: '主密码不能为空');
    }
    final remoteExists = await cloudHasBlob();
    if (remoteExists && !overwriteRemote) {
      // Cloud already has a backup — user should restore, not set up fresh.
      return const SyncOutcome(
        ok: false,
        message: '云端已存在备份，请改用「恢复」并输入主密码',
      );
    }
    final payload = await _serializeEnvelope();
    final blob = await SyncCrypto.encryptWithSalt(payload, password);
    final salt = SyncCrypto.extractSalt(blob)!;
    final key = await SyncCrypto.deriveKey(password, salt);
    final res = await _writeBlob(blob);
    if (!res.ok) {
      _lastError = res.msg;
      return SyncOutcome(
        ok: false,
        message: res.describe('写入云端失败'),
      );
    }
    await _cacheKey(CachedSyncKey(salt, key));
    await _tpAuth.markIdsBackedUp(SyncEnvelope.decode(payload)?.ids);
    await _storage.setSyncEnabled(true);
    _lastSyncAt = DateTime.now();
    await _storage.setSyncLastAt(_lastSyncAt!.toIso8601String());
    _lastError = null;
    if (jsonEncode(SyncEnvelope.decode(payload)?.ids?.toJson()) !=
        jsonEncode(_tpAuth.idsBinding?.toJson())) {
      final latest = await push();
      if (!latest.ok) return SyncOutcome(ok: false, message: latest.describe('最新 IDS 绑定备份失败'));
    }
    notifyListeners();
    return SyncOutcome(
      ok: true,
      message: remoteExists ? '云同步已开启（已覆盖云端备份）' : '云同步已开启',
    );
  }

  /// Explicit restore adopts cloud records, retaining local-only platforms.
  /// It never uploads: the user can inspect the restored bindings first.
  Future<SyncOutcome> restoreFromCloud() => _operations.protect(() => _restore());

  Future<SyncOutcome> restoreWithMasterPassword(String password) =>
      _operations.protect(() => _restore(password: password));

  Future<SyncOutcome> _restore({String? password}) async {
    final String? blob;
    try {
      blob = await _readBlob(requireReadableAccount: true);
    } catch (_) {
      return const SyncOutcome(ok: false, message: '无法读取云端备份，请检查网络或重新登录');
    }
    if (blob == null) {
      return const SyncOutcome(ok: false, message: '云端没有可恢复的备份');
    }
    final salt = SyncCrypto.extractSalt(blob);
    if (salt == null || blob.indexOf('.') <= 0) {
      return const SyncOutcome(ok: false, message: '云端备份格式损坏');
    }
    final plain = password != null
        ? await SyncCrypto.decryptWithSalt(blob, password)
        : _cachedKey == null
            ? null
            : await SyncCrypto.decrypt(blob.substring(blob.indexOf('.') + 1), _cachedKey!.key);
    if (plain == null) {
      if (password != null) return const SyncOutcome(ok: false, message: '主密码不正确');
      _needsRestore = true;
      await _clearCachedKey();
      notifyListeners();
      return const SyncOutcome(ok: false, message: '请输入主密码恢复云端备份', needMasterPassword: true);
    }
    final decoded = SyncEnvelope.decode(plain);
    if (decoded == null) {
      return const SyncOutcome(ok: false, message: '云端备份格式损坏');
    }
    // Resolve conflicts within the backup before making restore a new local
    // event. Promoting an account and its tombstone together would delete it.
    final remote =
        const SyncEnvelope(v: SyncSchema.current, accounts: [], tombstones: []).mergeWith(decoded);
    final local = SyncEnvelope.fromLocal(
      ecard: await _ecard?.readSyncBinding(),
      accounts: _tpAuth.accountsForSync,
      tombstones: _tombstones,
    );
    DateTime restoredAt(ThirdPartyPlatform platform, DateTime remoteTime) {
      final previous = [
        ...local.accounts.where((a) => a.platform == platform).map((a) => a.updatedAt),
        ...local.tombstones.where((t) => t.platform == platform).map((t) => t.deletedAt),
      ];
      return previous.any((time) => !time.isBefore(remoteTime))
          ? nextSyncTimestamp([...previous, remoteTime])
          : remoteTime;
    }

    final cloudCard = remote.ecard;
    final restored = SyncEnvelope(
      v: SyncSchema.current,
      accounts: remote.accounts
          .map(
            (a) => a.copyWith(
              updatedAt: restoredAt(a.platform, a.updatedAt),
              deviceId: _deviceId,
            ),
          )
          .toList(),
      tombstones: remote.tombstones
          .map(
            (t) => SyncTombstone(
              platform: t.platform,
              deletedAt: restoredAt(t.platform, t.deletedAt),
              deviceId: _deviceId,
            ),
          )
          .toList(),
      ecard: cloudCard == null
          ? null
          : EcardSyncBinding(
              openId: cloudCard.openId,
              channel: cloudCard.channel,
              updatedAt:
                  local.ecard != null && !local.ecard!.updatedAt.isBefore(cloudCard.updatedAt)
                      ? nextSyncTimestamp([local.ecard!.updatedAt, cloudCard.updatedAt])
                      : cloudCard.updatedAt,
              deviceId: _deviceId,
            ),
      unknown: remote.unknown,
    );
    await _applyRemoteState(local.mergeWith(restored), remote);
    if (password != null) {
      final key = await SyncCrypto.deriveKey(password, salt);
      await _cacheKey(CachedSyncKey(salt, key));
    }
    await _storage.setSyncEnabled(true);
    _lastSyncAt = DateTime.now();
    await _storage.setSyncLastAt(_lastSyncAt!.toIso8601String());
    _needsRestore = false;
    _lastError = null;
    _lastPushAt = DateTime.now();
    _debugLog('restored accounts=${remote.accounts.length}, ecard=${remote.ecard?.openId != null}');
    notifyListeners();
    return SyncOutcome(
      ok: true,
      message:
          remote.accounts.isEmpty && remote.ecard?.openId == null ? '云端备份中没有已绑定账号' : '已从云端恢复绑定',
    );
  }

  /// Change the master password: verify [oldPassword], re-encrypt current
  /// bindings with a fresh key (new salt), push, cache new key. Other devices'
  /// cached keys become invalid and will prompt for the new password.
  Future<SyncOutcome> changeMasterPassword(
    String oldPassword,
    String newPassword,
  ) async {
    if (newPassword.isEmpty) {
      return const SyncOutcome(ok: false, message: '新主密码不能为空');
    }
    final blob = await _readBlob();
    if (blob == null) {
      return const SyncOutcome(ok: false, message: '云端没有备份，无法验证旧密码');
    }
    final plain = await SyncCrypto.decryptWithSalt(blob, oldPassword);
    if (plain == null) {
      return const SyncOutcome(ok: false, message: '旧主密码不正确');
    }
    final newBlob = await SyncCrypto.encryptWithSalt(plain, newPassword);
    final salt = SyncCrypto.extractSalt(newBlob)!;
    final key = await SyncCrypto.deriveKey(newPassword, salt);
    final res = await _writeBlob(newBlob);
    if (!res.ok) {
      _lastError = res.msg;
      return SyncOutcome(ok: false, message: res.describe('写入云端失败'));
    }
    await _cacheKey(CachedSyncKey(salt, key));
    _lastSyncAt = DateTime.now();
    await _storage.setSyncLastAt(_lastSyncAt!.toIso8601String());
    _lastError = null;
    notifyListeners();
    return const SyncOutcome(ok: true, message: '主密码已更新');
  }

  /// Disable sync and wipe the cloud blob + local key. Bindings on this device
  /// are kept; other devices keep their local copies but lose cloud backup.
  Future<SyncOutcome> disable() async {
    final res = await _writeBlob(null);
    if (!res.ok) {
      _lastError = res.msg;
      return SyncOutcome(ok: false, message: res.describe('清除云端备份失败'));
    }
    await _clearCachedKey();
    _tombstones.clear();
    await _storage.saveThirdPartyTombstones(_tombstones);
    await _storage.setSyncEnabled(false);
    await _storage.setSyncLastAt('');
    _lastSyncAt = null;
    _lastError = null;
    notifyListeners();
    return const SyncOutcome(ok: true, message: '云同步已关闭');
  }

  /// Called by the UI after the user dismisses the restore banner without
  /// acting — keeps the flag so we don't re-show every rebuild, but still
  /// leaves sync "enabled" so a later password entry can restore.
  void acknowledgeNeedsRestore() {
    _needsRestore = false;
    notifyListeners();
  }

  /// Best-effort push with throttling. Called from binding mutation hooks
  /// (bind/unbind/renew) so the cloud stays in sync without spamming Casdoor.
  /// Swallows all errors — it's a background backup, not a user action.
  DateTime? _lastPushAt;
  Future<void> pushIfDue({Duration throttle = const Duration(seconds: 30)}) async {
    if (_applyingRemote) return;
    if (!enabled || _cachedKey == null) return;
    final now = DateTime.now();
    if (_lastPushAt != null && now.difference(_lastPushAt!) < throttle) return;
    _lastPushAt = now;
    try {
      await push();
    } catch (_) {
      // Background sync failures are non-fatal; the next explicit action retries.
    }
  }

  /// Force-push current bindings to the cloud, bypassing the throttle.
  /// Used after unbind/clearAll so a binding removal is immediately
  /// reflected in the cloud blob — without this, a throttled pushIfDue
  /// skip would leave the stale binding in the cloud, and the next boot's
  /// pull would restore it.
  Future<void> forcePush() async {
    if (_applyingRemote) return;
    if (!enabled || _cachedKey == null) return;
    _lastPushAt = DateTime.now();
    try {
      await push();
    } catch (_) {
      // Non-fatal — next explicit sync retries.
    }
  }
}
