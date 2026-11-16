import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final offlineAuthorizationBannerDismissedProvider =
    AsyncNotifierProvider<OfflineAuthorizationBannerController, bool>(
  OfflineAuthorizationBannerController.new,
);

final class OfflineAuthorizationBannerController extends AsyncNotifier<bool> {
  static const preferenceKey = 'geekpay.offline_authorization_banner_dismissed';

  @override
  Future<bool> build() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(preferenceKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> dismiss() async {
    state = const AsyncData(true);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(preferenceKey, true);
    } catch (_) {
      // Keep the in-process choice if platform preferences are unavailable.
    }
  }

  Future<void> reset() async {
    state = const AsyncData(false);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(preferenceKey);
    } catch (_) {
      // The next process falls back to showing the banner.
    }
  }
}
