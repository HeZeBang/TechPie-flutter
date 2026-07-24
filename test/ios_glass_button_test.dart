import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios_liquid/ios_glass_button.dart';

void main() {
  testWidgets('non-iOS action button uses Material control and handles taps', (
    WidgetTester tester,
  ) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IosGlassButton(
            label: 'Back up now',
            subtitle: 'Upload encrypted bindings',
            icon: Icons.cloud_upload_outlined,
            sfSymbol: 'arrow.up.circle',
            role: IosNativeButtonRole.prominent,
            onPressed: () => tapCount++,
          ),
        ),
      ),
    );

    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.text('Back up now'));
    expect(tapCount, 1);
  });

  testWidgets('iOS action button passes semantic state to UIKit', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IosGlassButton(
            label: 'Disable sync',
            subtitle: 'Remove the cloud backup',
            icon: Icons.cloud_off_outlined,
            sfSymbol: 'icloud.slash',
            role: IosNativeButtonRole.destructive,
            loading: true,
            onPressed: null,
            accessibilityLabel: 'Disable cloud sync',
          ),
        ),
      ),
    );

    final platformView = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(platformView.creationParams, {
      'sfSymbol': 'icloud.slash',
      'label': 'Disable sync',
      'subtitle': 'Remove the cloud backup',
      'role': 'destructive',
      'enabled': false,
      'loading': true,
      'accessibilityLabel': 'Disable cloud sync',
    });
    debugDefaultTargetPlatformOverride = null;
  });
}
