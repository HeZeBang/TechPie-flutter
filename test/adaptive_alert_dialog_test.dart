import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_alert_dialog.dart';

void main() {
  const channel = MethodChannel('cn_alert');
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final fails in [false, true]) {
    testWidgets('native alert maps actions and handles failure=$fails', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodCall? request;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        if (fails) throw PlatformException(code: 'unavailable');
        return {'index': 1};
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAdaptiveAlertDialog<String>(
                  context: context,
                  title: 'Remove account?',
                  message: 'This cannot be undone.',
                  actions: const [
                    AdaptiveAlertAction(label: ' Cancel ', value: 'cancel', isDefault: true),
                    AdaptiveAlertAction(
                      label: 'Remove',
                      value: 'remove',
                      isDestructive: true,
                    ),
                  ],
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(result, fails ? null : 'remove');
      expect(request?.method, 'show');
      final args = request!.arguments as Map;
      expect((args['actions'] as List).first['label'], 'Cancel');
      expect((args['actions'] as List).first['preferred'], true);
      expect((args['actions'] as List).last['style'], 'destructive');
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
