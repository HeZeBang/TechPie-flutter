import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/config/app_environment.dart';
import 'package:techpie/features/campus_card/core/config/payment_code_preferences.dart';
import 'package:techpie/features/campus_card/presentation/screens/me_screen.dart';
import 'package:techpie/features/campus_card/presentation/screens/security_limit_screen.dart';
import 'package:techpie/features/campus_card/presentation/screens/settings_screen.dart';
import 'package:techpie/features/campus_card/presentation/theme/theme.dart';
import 'package:techpie/features/campus_card/presentation/widgets/apple_wallet_components.dart';

void main() {
  Future<AppRuntime> productionLike() async {
    final base = await buildDemoRuntime();
    return AppRuntime(
      environment: AppEnvironment.production,
      capabilities: AppCapabilities.forEnvironment(AppEnvironment.production),
      auth: base.auth,
      cards: base.cards,
      paymentCodes: base.paymentCodes,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
      scanner: base.scanner,
      disposeRuntime: base.dispose,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    AppRuntime runtime,
    Widget screen,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(
          theme: GeekPayTheme.inherit(ThemeData.light()),
          home: screen,
        ),
      ),
    );
    for (var index = 0; index < 24; index++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets('production limits show separate card and QR controls', (
    tester,
  ) async {
    final runtime = await productionLike();
    addTearDown(runtime.dispose);
    await pumpScreen(tester, runtime, const SecurityLimitScreen());

    expect(find.text('卡消费限额'), findsOneWidget);
    expect(find.text('二维码消费限额'), findsOneWidget);
    expect(find.text('单笔限额'), findsNWidgets(2));
    expect(find.text('单日限额'), findsNWidgets(2));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('settings stay local and expose debug mode in debug builds', (
    tester,
  ) async {
    final runtime = await productionLike();
    addTearDown(runtime.dispose);
    await pumpScreen(tester, runtime, const SettingsScreen());

    expect(find.text('允许通知'), findsNothing);
    expect(find.text('启用付款码'), findsNothing);
    expect(find.text('语言'), findsNothing);
    expect(find.text('小额免密扫码跳过确认'), findsOneWidget);
    expect(find.text('调试模式'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);
    final rows = find.byType(AppleListRow);
    final heights = [
      for (var index = 0; index < 2; index++)
        tester.getSize(rows.at(index)).height,
    ];
    expect(heights.toSet(), hasLength(1));
  });

  testWidgets('profile uses a tail-four mask and never renders internal id', (
    tester,
  ) async {
    final runtime = await productionLike();
    addTearDown(runtime.dispose);
    await pumpScreen(tester, runtime, const MeScreen());

    expect(find.text('••••\u00A00001'), findsOneWidget);
    expect(find.textContaining('DEMO-CARD-0001'), findsNothing);
  });

  testWidgets('the maximum brightness switch defaults off and saves the choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final runtime = await productionLike();
    addTearDown(runtime.dispose);
    await pumpScreen(tester, runtime, const SettingsScreen());
    final control = find.byKey(const Key('maximize-payment-code-brightness'));
    final container = ProviderScope.containerOf(tester.element(control));

    expect(find.text('付款码最大亮度'), findsOneWidget);
    expect(
      container.read(maximizePaymentCodeBrightnessProvider).value,
      isFalse,
    );
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(
      container.read(maximizePaymentCodeBrightnessProvider).value,
      isTrue,
    );
    expect(
      (await SharedPreferences.getInstance())
          .getBool('geekpay.maximize_payment_code_brightness'),
      isTrue,
    );
  });
}
