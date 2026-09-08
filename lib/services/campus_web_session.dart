import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
  Future<void> _pending = Future.value();
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  String get _owner => node.account == null
      ? 'unbound'
      : '${node.identityKey}:${node.account!.boundAt.toIso8601String()}';

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
    if (storage.campusWebOwner == owner) return;
    final manager = CookieManager.instance();
    final webStorage = WebStorageManager.instance();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
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
      await manager.deleteAllCookies();
      await webStorage.deleteAllData();
    }
    await storage.setCampusWebOwner(owner);
    if (kDebugMode) {
      debugPrint('[CampusWeb] binding changed; web session cleared');
    }
  }

  Future<bool> useIdsSession() {
    if (!supported) return Future.value(false);
    final generation = node.generation;
    return _queue(() async {
      await _syncOwner();
      if (node.generation != generation) throw SessionFailure.changed;
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
      }
      if (node.generation != generation) {
        throw SessionFailure.changed;
      }
      return true;
    });
  }

  bool _schoolDomain(String domain) =>
      domain == 'shanghaitech.edu.cn' ||
      domain.endsWith('.shanghaitech.edu.cn');

  void dispose() => node.removeListener(_onBindingChanged);
}
