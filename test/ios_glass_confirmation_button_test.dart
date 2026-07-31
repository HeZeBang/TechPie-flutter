import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios_liquid/ios_glass_confirmation_button.dart';

void main() {
  const presenterChannel = MethodChannel('techpie/native_glass_presenter');

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS confirmation executes only after system confirmation', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var confirmed = false;
    MethodCall? nativeCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(presenterChannel, (call) async {
      nativeCall = call;
      return 1;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(presenterChannel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IosGlassConfirmationButton(
            label: 'Logout',
            confirmTitle: '退出登录?',
            confirmLabel: '退出',
            destructive: true,
            onConfirmed: () => confirmed = true,
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    expect(confirmed, isFalse);

    await tester.tap(find.text('Logout'));
    await tester.pump();

    expect(nativeCall?.method, 'showAlert');
    expect(confirmed, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
