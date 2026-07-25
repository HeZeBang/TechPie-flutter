import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/third_party_account.dart';
import 'auth_service.dart';
import 'storage_service.dart';
import 'sync_crypto.dart';
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
    return m == null || m.isEmpty
        ? '$shortLabel (HTTP ${httpStatus ?? "?"})'
        : '$shortLabel: $m';
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

  CachedSyncKey? _cachedKey;
  bool _needsRestore = false;
  DateTime? _lastSyncAt;
  String? _lastError;

  SyncService(this._auth, this._tpAuth, this._storage, {http.Client? client})
      : _client = client ?? http.Client();

  bool get enabled => _storage.syncEnabled;
  bool get hasLocalKey => _cachedKey != null;
  bool get needsRestore => _needsRestore;
  DateTime? get lastSyncAt => _lastSyncAt;
  /// Human-readable text from the most recent failed Casdoor call (for the
  /// "立即备份/恢复" toasts). Null when the last call succeeded.
  String? get lastError => _lastError;

  /// Load the cached derived key (if any) from secure storage. Call at boot.
  Future<void> loadCachedKey() async {
    final s = await _storage.loadSyncMasterKey();
    _cachedKey = await CachedSyncKey.fromStorageString(s);
    final iso = _storage.syncLastAt;
    _lastSyncAt = iso == null ? null : DateTime.tryParse(iso);
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
    // Visible in `flutter run` console. Sync HTTP traffic is NOT routed through
    // LoggingHttpClient (to keep the blob / bearer out of the request log), so
    // this is the only client-side trace of Casdoor responses. Safe to print:
    // update-user responses are just {status,msg,data} — no secrets.
    if (kDebugMode) debugPrint('[sync] $s');
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
      return jsonDecode(resp.body) as Map<String, dynamic>;
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
      if (await _auth.tryRenewSession()) {
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
      final snippet = resp.body.length > 200
          ? '${resp.body.substring(0, 200)}...'
          : resp.body;
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
  Future<String?> _readBlob() async {
    final token = await _requireToken();
    if (token == null) return null;
    final account = await _getAccount(token);
    if (account == null) return null;
    final props = account['data'] is Map
        ? (account['data'] as Map)['properties']
        : account['properties'];
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
    final user = (account['data'] is Map
        ? (account['data'] as Map)
        : account) as Map<String, dynamic>;
    final props =
        (user['properties'] as Map?)?.cast<String, String>() ?? <String, String>{};
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

  String _serializeAccounts() {
    final list = _tpAuth.accounts.map((a) => a.toJson()).toList();
    return jsonEncode(list);
  }

  List<ThirdPartyAccount> _parseAccounts(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map(
          (e) =>
              ThirdPartyAccount.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  /// Push current local bindings to the cloud (encrypted). Requires a cached
  /// key (i.e. the device has already been set up / restored). Returns a result
  /// whose [msg] carries Casdoor's error text on failure.
  Future<SyncCasdoorResult> push() async {
    if (!enabled || _cachedKey == null) {
      return const SyncCasdoorResult(false, msg: '云同步未开启或缺少主密码');
    }
    final payload = _serializeAccounts();
    // Reuse the cached salt so other devices' cached keys keep working.
    final salted = base64.encode(_cachedKey!.salt);
    final inner = await SyncCrypto.encrypt(payload, _cachedKey!.key);
    final blob = '$salted.$inner';
    final res = await _writeBlob(blob);
    _lastError = res.ok ? null : res.msg;
    if (res.ok) {
      _lastSyncAt = DateTime.now();
      await _storage.setSyncLastAt(_lastSyncAt!.toIso8601String());
      notifyListeners();
    }
    return res;
  }

  /// Pull the cloud blob and restore bindings locally. Throws
  /// [NeedMasterPassword] if no key is cached on this device.
  Future<void> pull() async {
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
    final accounts = _parseAccounts(plain);
    await _tpAuth.replaceAll(accounts);
    _lastSyncAt = DateTime.now();
    await _storage.setSyncLastAt(_lastSyncAt!.toIso8601String());
    _needsRestore = false;
    notifyListeners();
  }

  /// First-time setup on a device that has no cloud blob yet: derive a key
  /// from [password] (fresh salt), cache it, and push current bindings.
  Future<SyncOutcome> setupWithMasterPassword(String password) async {
    if (password.isEmpty) {
      return const SyncOutcome(ok: false, message: '主密码不能为空');
    }
    if (await cloudHasBlob()) {
      // Cloud already has a backup — user should restore, not set up fresh.
      return const SyncOutcome(
        ok: false,
        message: '云端已存在备份，请改用「恢复」并输入主密码',
      );
    }
    final payload = _serializeAccounts();
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
    await _storage.setSyncEnabled(true);
    _lastSyncAt = DateTime.now();
    await _storage.setSyncLastAt(_lastSyncAt!.toIso8601String());
    _lastError = null;
    notifyListeners();
    return const SyncOutcome(ok: true, message: '云同步已开启');
  }

  /// Restore on a device that has a cloud blob but no cached key: verify
  /// [password] decrypts the blob, cache the key, pull bindings.
  Future<SyncOutcome> restoreWithMasterPassword(String password) async {
    final blob = await _readBlob();
    if (blob == null) {
      return const SyncOutcome(ok: false, message: '云端没有可恢复的备份');
    }
    final plain = await SyncCrypto.decryptWithSalt(blob, password);
    if (plain == null) {
      return const SyncOutcome(ok: false, message: '主密码不正确');
    }
    final salt = SyncCrypto.extractSalt(blob)!;
    final key = await SyncCrypto.deriveKey(password, salt);
    await _cacheKey(CachedSyncKey(salt, key));
    final accounts = _parseAccounts(plain);
    await _tpAuth.replaceAll(accounts);
    await _storage.setSyncEnabled(true);
    _lastSyncAt = DateTime.now();
    await _storage.setSyncLastAt(_lastSyncAt!.toIso8601String());
    _needsRestore = false;
    _lastError = null;
    notifyListeners();
    return const SyncOutcome(ok: true, message: '已从云端恢复绑定');
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
    if (!enabled || _cachedKey == null) return;
    _lastPushAt = DateTime.now();
    try {
      await push();
    } catch (_) {
      // Non-fatal — next explicit sync retries.
    }
  }
}
