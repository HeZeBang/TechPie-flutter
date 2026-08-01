import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_segmented_control.dart';
import 'package:techpie/widgets/adaptive_switch.dart';

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
          body: AdaptiveSwitch(
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
          body: AdaptiveSegmentedControl(
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
