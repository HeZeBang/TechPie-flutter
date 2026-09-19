import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/core/config/offline_authorization_banner_controller.dart';

void main() {
  test('dismissal persists until an explicit lifecycle reset', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(offlineAuthorizationBannerDismissedProvider.future),
      isFalse,
    );
    await container
        .read(offlineAuthorizationBannerDismissedProvider.notifier)
        .dismiss();
    expect(
      await container.read(offlineAuthorizationBannerDismissedProvider.future),
      isTrue,
    );
    expect(
      (await SharedPreferences.getInstance()).getBool(
        OfflineAuthorizationBannerController.preferenceKey,
      ),
      isTrue,
    );

    await container
        .read(offlineAuthorizationBannerDismissedProvider.notifier)
        .reset();
    expect(
      await container.read(offlineAuthorizationBannerDismissedProvider.future),
      isFalse,
    );
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        OfflineAuthorizationBannerController.preferenceKey,
      ),
      isFalse,
    );
  });
}
