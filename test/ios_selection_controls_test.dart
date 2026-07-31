import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios_liquid/ios_glass_switch.dart';
import 'package:techpie/widgets/ios_liquid/ios_native_segmented_control.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS switch is composited and reports changes', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    bool? changedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IosGlassSwitch(
            value: false,
            onChanged: (value) => changedValue = value,
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    await tester.tap(find.byType(CupertinoSwitch));
    expect(changedValue, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS segmented control is composited and reports selection', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    int? selectedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IosNativeSegmentedControl(
            value: 0,
            segments: const ['密码登录', '短信登录'],
            onChanged: (value) => selectedValue = value,
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    await tester.tap(find.text('短信登录'));
    await tester.pumpAndSettle();
    expect(selectedValue, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}
