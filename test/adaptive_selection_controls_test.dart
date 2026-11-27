import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/platform.dart';
import 'package:techpie/widgets/adaptive_checkbox.dart';
import 'package:techpie/widgets/adaptive_segmented_control.dart';
import 'package:techpie/widgets/adaptive_slider.dart';
import 'package:techpie/widgets/adaptive_switch.dart';
import 'package:techpie/widgets/design_system/design_system.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    debugForceDirectIosUiKitViews = false;
  });

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

  testWidgets('iOS segmented control renders TpSegmentedControl and reports selection', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    int? selectedValue;

    try {
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

      expect(find.byType(TpSegmentedControl), findsOneWidget);
      expect(find.byType(CNSegmentedControl), findsNothing);
      await tester.tap(find.text('短信登录'));
      // Drain AppHaptics.play's 300ms platform channel timeout timer.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(selectedValue, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS direct UIKit flag renders direct native UiKitViews for pre-iOS 26', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    debugForceDirectIosUiKitViews = true;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdaptiveSwitch(value: true, onChanged: (_) {}),
                AdaptiveSegmentedControl(
                  value: 1,
                  segments: const ['A', 'B'],
                  onChanged: (_) {},
                ),
                AdaptiveSlider(
                  value: 0.5,
                  min: 0,
                  max: 1,
                  onChanged: (_) {},
                ),
                AdaptiveCheckbox(
                  value: true,
                  semanticLabel: '同意',
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      final views = tester.widgetList<UiKitView>(find.byType(UiKitView)).toList();
      expect(
        views.map((v) => v.viewType),
        containsAll([
          'CupertinoNativeSwitch',
          'CupertinoNativeSlider',
        ]),
      );
      expect(find.byType(TpSegmentedControl), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    } finally {
      debugForceDirectIosUiKitViews = false;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS selection controls use native AppKitView types and TpSegmentedControl', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdaptiveSwitch(value: false, onChanged: (_) {}),
                AdaptiveSegmentedControl(
                  value: 0,
                  segments: const ['概览', '明细'],
                  onChanged: (_) {},
                ),
                AdaptiveSlider(
                  value: 10,
                  min: 0,
                  max: 100,
                  divisions: 10,
                  onChanged: (_) {},
                ),
                AdaptiveCheckbox(value: false, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      );

      final views =
          tester.widgetList<AppKitView>(find.byType(AppKitView)).toList();
      expect(
        views.map((v) => v.viewType),
        containsAll([
          'TechPieMacSwitch',
          'TechPieMacSlider',
          'TechPieMacCheckbox',
        ]),
      );
      expect(find.byType(TpSegmentedControl), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(SegmentedButton<int>), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android keeps Material Switch, Slider, Checkbox and unified TpSegmentedControl', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdaptiveSwitch(value: true, onChanged: (_) {}),
                AdaptiveSegmentedControl(
                  value: 0,
                  segments: const ['A', 'B'],
                  onChanged: (_) {},
                ),
                AdaptiveSlider(value: 0.4, onChanged: (_) {}),
                AdaptiveCheckbox(value: true, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(TpSegmentedControl), findsOneWidget);
      expect(find.byType(SegmentedButton<int>), findsNothing);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.byType(AppKitView), findsNothing);
      expect(find.byType(UiKitView), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
