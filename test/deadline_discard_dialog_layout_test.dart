import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_alert_dialog.dart';

void main() {
  testWidgets(
    'Deadline discard dialog centers the title and sizes actions equally',
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
