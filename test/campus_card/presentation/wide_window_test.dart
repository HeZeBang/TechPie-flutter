import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/pages/campus_card_page.dart';
import 'package:techpie/widgets/blurred_app_bar.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

/// A window wider than the page's readable measure is where the page frame and
/// the navigation bar have to part ways: the bar belongs to the window (every
/// other TechPie page's does), the column of content does not.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  const window = Size(1400, 1200);

  Future<void> pumpEcard(WidgetTester tester) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final runtime = await buildDemoRuntime();
    addTearDown(runtime.dispose);
    await runtime.auth.signIn(const DemoAuthCredential());

    await tester.pumpWidget(MaterialApp(home: CampusCardPage(runtime: runtime)));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets('the eCard bar covers a wide window, the content stays readable', (
    tester,
  ) async {
    await pumpEcard(tester);

    final bar = find.byType(BlurredAppBar);
    expect(bar, findsOneWidget);
    expect(
      tester.getSize(bar).width,
      window.width,
      reason: 'the bar spans the window, like every other TechPie page bar',
    );

    final pass = find.byKey(const Key('expanded-payment-pass'));
    expect(pass, findsOneWidget);
    expect(
      tester.getSize(pass).width,
      lessThanOrEqualTo(560),
      reason: 'the content keeps its readable measure',
    );
    expect(
      tester.getCenter(pass).dx,
      closeTo(window.width / 2, 1),
      reason: 'and stays centred under the full-width bar',
    );
  });

  testWidgets('the iOS header covers a wide window as well', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await pumpEcard(tester);

    final bar = find.byType(IosNativeNavigationBar);
    expect(bar, findsOneWidget);
    expect(tester.getSize(bar).width, window.width);

    // The framework checks its own debug variables at the end of the body, so
    // the override goes back inside it, not in a tear-down.
    debugDefaultTargetPlatformOverride = null;
  });
}
