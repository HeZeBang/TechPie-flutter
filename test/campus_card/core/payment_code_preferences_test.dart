import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/core/config/payment_code_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('maximum pay code brightness defaults to disabled', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      await container.read(maximizePaymentCodeBrightnessProvider.future),
      isFalse,
    );
  });

  test('enabled and disabled choices survive recreating the provider',
      () async {
    var container = ProviderContainer();
    await container.read(maximizePaymentCodeBrightnessProvider.future);
    await container
        .read(maximizePaymentCodeBrightnessProvider.notifier)
        .setEnabled(true);
    container.dispose();

    container = ProviderContainer();
    expect(
      await container.read(maximizePaymentCodeBrightnessProvider.future),
      isTrue,
    );
    await container
        .read(maximizePaymentCodeBrightnessProvider.notifier)
        .setEnabled(false);
    container.dispose();

    container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      await container.read(maximizePaymentCodeBrightnessProvider.future),
      isFalse,
    );
  });
}
