import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_button.dart';
import 'package:techpie/widgets/design_system/tp_press_scale.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('non-iOS action button uses Material control and handles taps', (
    WidgetTester tester,
  ) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveButton(
            label: 'Back up now',
            subtitle: 'Upload encrypted bindings',
            icon: Icons.cloud_upload_outlined,
            sfSymbol: 'arrow.up.circle',
            role: AdaptiveButtonRole.prominent,
            onPressed: () => tapCount++,
          ),
        ),
      ),
    );

    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.text('Back up now'));
    expect(tapCount, 1);
  });

  testWidgets('iOS action button uses composited Cupertino state', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdaptiveButton(
            label: 'Disable sync',
            subtitle: 'Remove the cloud backup',
            icon: Icons.cloud_off_outlined,
            sfSymbol: 'icloud.slash',
            role: AdaptiveButtonRole.destructive,
            loading: true,
            onPressed: null,
            accessibilityLabel: 'Disable cloud sync',
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    final button = tester.widget<CupertinoButton>(find.byType(CupertinoButton));
    expect(button.onPressed, isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'iOS prominent AdaptiveButton paints fill on CupertinoButton directly and wraps in TpPressScale',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var tapCount = 0;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AdaptiveButton(
                label: 'Connect account',
                icon: Icons.login,
                sfSymbol: 'person.crop.circle.badge.checkmark',
                role: AdaptiveButtonRole.prominent,
                onPressed: () => tapCount++,
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(CupertinoButton);
      final button = tester.widget<CupertinoButton>(buttonFinder);
      expect(button.color, isNotNull);
      expect(button.pressedOpacity, lessThan(1.0));
      expect(
        find.ancestor(
          of: buttonFinder,
          matching: find.byType(TpPressScale),
        ),
        findsOneWidget,
      );

      // Hold gesture verifies tactile press scale engages without blocking tap.
      final center = tester.getCenter(buttonFinder);
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final pressScaleTransform = tester.widget<Transform>(
        find.descendant(
          of: find.byType(TpPressScale),
          matching: find.byType(Transform),
        ),
      );
      expect(pressScaleTransform.transform.storage[0], lessThan(0.99));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapCount, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
