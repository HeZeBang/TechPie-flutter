import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shares the activity screen flag across overlapping player lifetimes.
class ElrcScreenAwake {
  ElrcScreenAwake({Future<void> Function(bool)? setEnabled})
      : _setEnabled = setEnabled ?? _setAndroidEnabled;

  static final shared = ElrcScreenAwake();
  static const _channel = MethodChannel('techpie/elrc_playback');
  final Future<void> Function(bool) _setEnabled;
  final _owners = <Object>{};
  Future<void> _pending = Future.value();
  bool _requested = false;

  void setActive(Object owner, bool active) {
    if (active) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    final enabled = _owners.isNotEmpty;
    if (_requested == enabled) return;
    _requested = enabled;
    // Preserve order so a late enable cannot overtake the final release.
    unawaited(_pending = _pending.then((_) async {
      try {
        await _setEnabled(enabled);
      } catch (_) {/* Screen control is unavailable on unsupported hosts. */}
    }),);
  }

  @visibleForTesting
  Future<void> get settled => _pending;

  static Future<void> _setAndroidEnabled(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('setKeepScreenOn', enabled);
  }
}
