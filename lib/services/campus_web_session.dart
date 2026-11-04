import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewController, WebViewCookieManager;

import 'auth_service.dart';
import 'session/session_node.dart';
import 'storage_service.dart';

/// Owns the browser-side half of the campus web session: the cookie store every
/// embedded webview shares.
///
/// It is deliberately *not* a credential store — credentials live in the
/// [SessionNode] tree, and pages read their cookies from there (see
/// `CampusSessionHandle`). What this class does is reset that shared store when
/// the primary account or its IDS binding changes, so a page opened under a
/// new account cannot inherit the previous one's campus session.
///
/// The reset is a full wipe of the store: Android and OHOS cannot enumerate
/// cookies by domain, and the store is private to this app — the system browser
/// is unaffected, but another embedded login (ELRC, a fresh Casdoor round trip)
/// has to sign in again afterwards.
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
  bool _storageClearDue = false;

  /// Platforms whose embedded webviews share one app-private store we can wipe:
  /// iOS, macOS and Android through webview_flutter, OHOS through its ArkWeb
  /// plugin. Desktop windows own their store and are not covered.
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform.name == 'ohos');

  String get _owner {
    final userId = _auth?.session?.userId;
    if (userId == null) return 'signed-out';
    final binding = node.account == null || node.account!.raw['authMethod'] != 'passkey'
        ? 'unbound'
        : '${node.account!.account}:${node.account!.boundAt.toIso8601String()}';
    return jsonEncode([userId, binding]);
  }

  String get owner => '$_authRevision:$_owner';

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
    _pending = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  /// Wipes the shared store when the campus account changed since the last wipe.
  /// Pages await this before they load, so nothing they inject can be wiped
  /// after the fact.
  Future<void> prepare() => !supported ? Future.value() : _queue(_syncOwner);

  Future<void> _syncOwner() async {
    final owner = _owner;
    final revision = _authRevision;
    if (storage.campusWebOwner == owner && _clearedAuthRevision == revision) {
      return;
    }
    await WebViewCookieManager().clearCookies();
    _storageClearDue = true;
    await storage.setCampusWebOwner(owner);
    _clearedAuthRevision = revision;
    if (kDebugMode) {
      debugPrint('[CampusWeb] binding changed; web session cleared');
    }
  }

  /// Wipes [controller]'s local storage when an account change still owes one.
  ///
  /// The plugin only reaches local storage through a controller, so the page
  /// that is about to load performs it — before it injects anything, so the new
  /// account's cookies are never the collateral. Local storage of the previous
  /// account would otherwise outlive the cookie wipe and be readable by whatever
  /// origin-scoped code the next account loads.
  Future<void> clearLocalStorageIfDue(WebViewController controller) async {
    if (!_storageClearDue) return;
    _storageClearDue = false;
    await controller.clearLocalStorage();
  }

  void dispose() {
    _auth?.removeListener(_onPrimaryAccountChanged);
    node.removeListener(_onBindingChanged);
  }
}
