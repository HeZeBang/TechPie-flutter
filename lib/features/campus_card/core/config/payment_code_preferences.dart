import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final maximizePaymentCodeBrightnessProvider =
    AsyncNotifierProvider<MaximizePaymentCodeBrightnessController, bool>(
  MaximizePaymentCodeBrightnessController.new,
);

final class MaximizePaymentCodeBrightnessController
    extends AsyncNotifier<bool> {
  static const _key = 'geekpay.maximize_payment_code_brightness';

  @override
  Future<bool> build() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, enabled);
    state = AsyncData(enabled);
  }
}

/// Whether the pass shows a locally generated code straight away and hands the
/// surface over to the online code as soon as it arrives ("离线码优先"). On by
/// default: the local code is the fast path, the online one takes over.
///
/// Producing a local code consumes one offline authorization, so this is a
/// deliberate trade the user makes: an instant code on a slow campus network,
/// paid for in offline uses.
final offlineCodeFirstProvider =
    AsyncNotifierProvider<OfflineCodeFirstController, bool>(
  OfflineCodeFirstController.new,
);

final class OfflineCodeFirstController extends AsyncNotifier<bool> {
  static const preferenceKey = 'geekpay.offline_code_first';

  @override
  Future<bool> build() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(preferenceKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, enabled);
    state = AsyncData(enabled);
  }
}
