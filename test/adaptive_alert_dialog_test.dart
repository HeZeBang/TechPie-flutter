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

  testWidgets(
    'centers confirmation text and divides the action width equally',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const title = '放弃未保存的修改？';
      const continueLabel = '继续编辑';
      const discardLabel = '放弃并退出';
      double? previousButtonWidth;

      for (final (width, textScale) in [(400.0, 1.0), (300.0, 2.0)]) {
        tester.view.physicalSize = Size(width, 720);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAdaptiveAlertDialog<bool>(
                    context: context,
                    title: title,
                    message: '',
                    centerContent: true,
                    actions: const [
                      AdaptiveAlertAction(label: continueLabel, value: false, isDefault: true),
                      AdaptiveAlertAction(label: discardLabel, value: true, isDestructive: true),
                    ],
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final dialog = find.byType(AlertDialog);
        final titleText = find.text(title);
        final continueAction = find.widgetWithText(FilledButton, continueLabel);
        final discardAction = find.widgetWithText(TextButton, discardLabel);
        final first = tester.getRect(continueAction);
        final second = tester.getRect(discardAction);
        final center = tester.getCenter(dialog).dx;

        expect(tester.widget<Text>(titleText).textAlign, TextAlign.center);
        expect(tester.getCenter(titleText).dx, closeTo(center, 0.01));
        expect(first.center.dy, closeTo(second.center.dy, 0.01));
        expect(first.height, closeTo(second.height, 0.01));
        expect(first.width, closeTo(second.width, 0.01));
        expect(first.expandToInclude(second).center.dx, closeTo(center, 0.01));
        expect(tester.getCenter(find.text(continueLabel)).dx, closeTo(first.center.dx, 0.01));
        expect(tester.getCenter(find.text(discardLabel)).dx, closeTo(second.center.dx, 0.01));
        if (previousButtonWidth != null) expect(first.width, lessThan(previousButtonWidth));
        previousButtonWidth = first.width;

        await tester.tap(continueAction);
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
