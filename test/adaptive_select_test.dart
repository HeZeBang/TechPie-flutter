import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_select.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS select uses a composited Cupertino action sheet', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String? selectedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSelect(
            value: 'system',
            options: const [
              AdaptiveSelectOption(value: 'system', label: 'System'),
              AdaptiveSelectOption(value: 'dark', label: 'Dark'),
            ],
            onChanged: (value) => selectedValue = value,
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(selectedValue, 'dark');
    debugDefaultTargetPlatformOverride = null;
  });
}
