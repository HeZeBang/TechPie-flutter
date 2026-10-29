import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_segmented_control.dart';
import 'package:techpie/widgets/adaptive_switch.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS switch is a native UISwitch and reports changes', (
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

    final control = tester.widget<CNSwitch>(find.byType(CNSwitch));
    expect(control.value, isFalse);
    control.onChanged(true);
    expect(changedValue, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS segmented control is a native UISegmentedControl and reports selection', (
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

    final control =
        tester.widget<CNSegmentedControl>(find.byType(CNSegmentedControl));
    expect(control.labels, ['密码登录', '短信登录']);
    expect(control.selectedIndex, 0);
    control.onValueChanged(1);
    expect(selectedValue, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}
