import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'debug_mode_features.dart';

final debugModeProvider = NotifierProvider<DebugModeController, bool>(
  DebugModeController.new,
);

final class DebugModeController extends Notifier<bool> {
  static const _key = 'geekpay.debug_mode';

  @override
  bool build() {
    if (debugModeFeaturesAvailable) unawaited(_restore());
    return false;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? false;
    } catch (_) {
      // Widget tests may run without a platform preference channel.
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!debugModeFeaturesAvailable) return;
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
