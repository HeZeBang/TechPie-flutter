import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'third_party_auth_service.dart';

/// Owns the WebView identity used by CpDaily-backed school features.
/// Neither GeekPie logout nor anonymous ELRC playback changes this identity.
class SchoolWebSessionService {
  SchoolWebSessionService(this._auth, {Future<void> Function()? clearCookies})
      : _clearCookies = clearCookies ?? _clearPlatformCookies {
    _identity = _currentIdentity;
    _auth.addListener(_bindingChanged);
  }

  final ThirdPartyAuthService _auth;
  final Future<void> Function() _clearCookies;
  final _pages = <Future<void> Function()>{};
  final _retiring = <Future<void> Function()>{};
  Future<void> _pending = Future.value();
  late (String, String?)? _identity;
  int _generation = 0;
  bool _needsClear = true;
  bool _disposed = false;

  int get generation => _generation;
  bool isCurrent(int value) => !_disposed && value == _generation;

  (String, String?)? get _currentIdentity {
    final account = _auth.cpdailyNode.account;
    return account == null ? null : (account.account, account.sid);
  }

  static Future<void> _clearPlatformCookies() async {
    // Follow the same Flutter target as the view, including in widget tests.
    // These pinned plugins expose only whole-jar clearing. Do it on school
    // identity changes (and first use after boot), not on every feature open.
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      await WebviewWindow.clearAll();
    } else {
      await WebViewCookieManager().clearCookies();
    }
  }

  VoidCallback attach(Future<void> Function() invalidate) {
    _pages.add(invalidate);
    return () => _pages.remove(invalidate);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _clear() async {
    final current = _generation;
    await Future.wait(
      [for (final close in _retiring.toList()) _closePage(close)],
    );
    await _clearCookies();
    if (isCurrent(current)) _needsClear = false;
  }

  void _bindingChanged() {
    final next = _currentIdentity;
    if (_identity == next) return;
    _identity = next;
    _generation++;
    _needsClear = true;
    unawaited(_invalidateAndClear());
  }

  Future<void> _invalidateAndClear() async {
    // Hide/stop old documents immediately, before any asynchronous cleanup.
    _retiring.addAll(_pages);
    final closing = [for (final invalidate in _pages) _closePage(invalidate)];
    _pages.clear();
    final closed = _waitForClosed(closing);
    try {
      await _enqueue(() async {
        final error = await closed;
        if (error != null) throw error;
        await _clear();
      });
    } catch (_) {
      _needsClear = true;
    }
  }

  Future<void> _closePage(Future<void> Function() invalidate) async {
    await invalidate();
    _retiring.remove(invalidate);
  }

  Future<Object?> _waitForClosed(List<Future<void>> closing) async {
    return await Future.wait(closing).then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
  }

  /// Serializes resets and cookie writes. Read credentials only after cleanup,
  /// so a queued page cannot inject the account captured before a cloud restore.
  Future<void> open({
    required int generation,
    required bool Function() isOpen,
    Future<void> Function()? prepare,
    required Future<void> Function(WebViewCookie) setCookie,
    required Future<void> Function() load,
  }) =>
      _enqueue(() async {
        bool current() => isCurrent(generation) && isOpen();
        if (!current()) return;
        if (_needsClear) await _clear();
        if (!current()) return;
        await prepare?.call();
        if (!current()) return;
        final provider = _auth.cpdailyNode.cookieProvider;
        if (provider != null && !provider.isEmpty) {
          final domain = provider.domain.isEmpty
              ? 'ids.shanghaitech.edu.cn'
              : provider.domain;
          for (final part in provider.cookies.split(';')) {
            final index = part.indexOf('=');
            if (index <= 0) continue;
            final name = part.substring(0, index).trim();
            final value = part.substring(index + 1).trim();
            if (name.isEmpty || value.isEmpty) continue;
            await setCookie(
              WebViewCookie(name: name, value: value, domain: domain),
            );
            if (!current()) return;
          }
        }
        await load();
      });

  void dispose() {
    _disposed = true;
    _auth.removeListener(_bindingChanged);
    _pages.clear();
  }
}
