import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'auth_service.dart';
import 'session/session_failure.dart';
import 'session/session_node.dart';
import 'storage_service.dart';

/// Coordinates the App's campus WebViews, which share one native cookie store.
class CampusWebSession {
  CampusWebSession(this.node, this.storage) {
    node.addListener(_onBindingChanged);
  }

  final SessionNode node;
  final StorageService storage;
  AuthService? _auth;
  String? _primaryUserId;
  int _authRevision = 0;
  int _clearedAuthRevision = 0;
  Future<void> _pending = Future.value();
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.android);
  String get _owner {
    final userId = _auth?.session?.userId;
    if (userId == null) return 'signed-out';
    final binding = node.account == null
        ? 'unbound'
        : '${node.identityKey}:${node.account!.boundAt.toIso8601String()}';
    return jsonEncode([userId, binding]);
  }

  void attachAuth(AuthService auth) {
    if (identical(_auth, auth)) return;
    _auth?.removeListener(_onPrimaryAccountChanged);
    _auth = auth;
    _primaryUserId = auth.session?.userId;
    auth.addListener(_onPrimaryAccountChanged);
    _onBindingChanged();
  }

  void _onPrimaryAccountChanged() {
    final userId = _auth?.session?.userId;
    if (_primaryUserId == userId) return;
    _primaryUserId = userId;
    _authRevision++;
    node.cancelPendingRequests();
    _onBindingChanged();
  }

  void _onBindingChanged() {
    unawaited(
      prepare().catchError((Object _) {
        if (kDebugMode) debugPrint('[CampusWeb] session reset failed');
      }),
    );
  }

  Future<T> _queue<T>(Future<T> Function() action) {
    final operation = _pending.then((_) => action());
    _pending =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  Future<void> prepare() => !supported ? Future.value() : _queue(_syncOwner);

  Future<void> _syncOwner() async {
    final owner = _owner;
    final revision = _authRevision;
    if (storage.campusWebOwner == owner && _clearedAuthRevision == revision) {
      return;
    }
    final manager = CookieManager.instance();
    final webStorage = WebStorageManager.instance();
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      for (final cookie in await manager.getAllCookies()) {
        final domain = cookie.domain ?? '';
        if (!_schoolDomain(domain)) continue;
        await manager.deleteCookie(
          url: WebUri('https://${domain.replaceFirst(RegExp(r'^\.'), '')}/'),
          name: cookie.name,
          domain: domain,
          path: cookie.path ?? '/',
        );
      }
      final records =
          await webStorage.fetchDataRecords(dataTypes: WebsiteDataType.ALL);
      await webStorage.removeDataFor(
        dataTypes: WebsiteDataType.ALL,
        dataRecords: records
            .where((record) => _schoolDomain(record.displayName ?? ''))
            .toList(),
      );
    } else {
      // Android cannot enumerate cookie domains/paths. Its shared App store
      // is reset on binding replacement, including other embedded web logins.
      // False means the store was already empty, not that deletion failed.
      await manager.deleteAllCookies();
      await webStorage.deleteAllData();
    }
    await storage.setCampusWebOwner(owner);
    _clearedAuthRevision = revision;
    if (kDebugMode) {
      debugPrint('[CampusWeb] binding changed; web session cleared');
    }
  }

  Future<bool> useIdsSession() {
    if (!supported) return Future.value(false);
    final owner = _owner;
    final revision = _authRevision;
    final generation = node.generation;
    final epoch = node.epoch;
    return _queue(() async {
      await _syncOwner();
      void checkOwner() {
        if (_auth?.isLoggedIn != true ||
            _authRevision != revision ||
            _owner != owner ||
            node.generation != generation) {
          throw SessionFailure.changed;
        }
      }

      checkOwner();
      if (node.account == null) return false;
      // Reuse the existing single-flight renewal before handing IDS its TGC.
      final renewed = await node.renewIfNeeded(epoch);
      checkOwner();
      if (!renewed) {
        if (node.lastRenewWasCredentialError) return false;
        throw node.lastFailure ?? SessionFailure.unavailable;
      }
      final tgc = node.rawFields['tgc'] as String? ?? '';
      if (tgc.isEmpty) return false;
      for (final name in const ['CASTGC', 'AUTHTGC']) {
        final saved = await CookieManager.instance().setCookie(
          url: WebUri('https://ids.shanghaitech.edu.cn/authserver/'),
          name: name,
          value: tgc,
          path: '/authserver',
          isSecure: true,
          isHttpOnly: true,
        );
        if (!saved) throw SessionFailure.unavailable;
        checkOwner();
      }
      return true;
    });
  }

  bool _schoolDomain(String domain) =>
      domain == 'shanghaitech.edu.cn' ||
      domain.endsWith('.shanghaitech.edu.cn');

  void dispose() {
    _auth?.removeListener(_onPrimaryAccountChanged);
    node.removeListener(_onBindingChanged);
  }
}
