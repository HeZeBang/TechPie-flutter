import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_alert_dialog.dart';

void main() {
  const presenterChannel = MethodChannel('techpie/native_glass_presenter');

  testWidgets('iOS fallback keeps Cupertino actions and returns selection', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String? result;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      presenterChannel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showAdaptiveAlertDialog<String>(
                context: context,
                title: 'Remove account?',
                message: 'This cannot be undone.',
                actions: const [
                  AdaptiveAlertAction<String>(
                    label: 'Cancel',
                    value: 'cancel',
                  ),
                  AdaptiveAlertAction<String>(
                    label: 'Remove',
                    value: 'remove',
                    isDestructive: true,
                  ),
                ],
              ).then((value) => result = value),
            ),
            child: const Text('Show dialog'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show dialog'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    final destructiveAction = tester.widget<CupertinoDialogAction>(
      find.widgetWithText(CupertinoDialogAction, 'Remove'),
    );
    expect(destructiveAction.isDestructiveAction, isTrue);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(result, 'remove');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(presenterChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });
}
