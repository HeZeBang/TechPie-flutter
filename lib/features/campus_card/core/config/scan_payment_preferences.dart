import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final skipScanConfirmationProvider =
    NotifierProvider<SkipScanConfirmationController, bool>(
  SkipScanConfirmationController.new,
);

final class SkipScanConfirmationController extends Notifier<bool> {
  static const _key = 'geekpay.skip_scan_confirmation';
  int _revision = 0;

  @override
  bool build() {
    unawaited(_restore(++_revision));
    return false;
  }

  Future<void> _restore(int revision) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (revision == _revision) state = preferences.getBool(_key) ?? false;
    } catch (_) {
      // Tests may run without a platform preference channel.
    }
  }

  Future<void> setEnabled(bool enabled) async {
    ++_revision;
    state = enabled;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_key, enabled);
    } catch (_) {
      // The in-memory choice remains valid for this app process.
    }
  }
}
