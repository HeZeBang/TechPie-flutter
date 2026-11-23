import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_text_area.dart';
import 'package:techpie/widgets/adaptive_text_field_group.dart';
import 'package:techpie/widgets/secure_password_field.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets(
      'iOS grouped fields use Flutter text input and update controllers', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.platformDispatcher.brieflyShowPasswordTestValue = true;
    addTearDown(tester.binding.platformDispatcher.resetBrieflyShowPassword);
    final account = TextEditingController();
    final password = TextEditingController();
    addTearDown(account.dispose);
    addTearDown(password.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveTextFieldGroup(
            items: [
              AdaptiveTextFieldGroupItem(
                controller: account,
                placeholder: '学号',
              ),
              AdaptiveTextFieldGroupItem(
                controller: password,
                placeholder: '密码',
                obscureText: true,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.byType(SecurePasswordField), findsOneWidget);
    final groupRect = tester.getRect(find.byType(AdaptiveTextFieldGroup));
    final lineRect = tester.getRect(
      find.descendant(
        of: find.byType(Divider),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect(lineRect.left - groupRect.left, closeTo(16, 0.01));
    expect(groupRect.right - lineRect.right, closeTo(16, 0.01));
    expect(lineRect.center.dx, closeTo(groupRect.center.dx, 0.01));
    expect(lineRect.center.dy, closeTo(groupRect.center.dy, 0.01));
    await tester.enterText(find.byType(CupertinoTextField).first, '20260001');
    expect(account.text, '20260001');
    final secureEditable = find.descendant(
      of: find.byType(SecurePasswordField),
      matching: find.byWidgetPredicate((widget) => widget is EditableText),
    );
    await tester.tap(secureEditable);
    await tester.pump();
    const secret = 'aB9!secret';
    for (var i = 1; i <= secret.length; i++) {
      tester.testTextInput.enterText(secret.substring(0, i));
      await tester.pump();
      expect(
        tester.state<EditableTextState>(secureEditable).renderEditable.text!.toPlainText(),
        '•' * i,
      );
    }
    expect(password.text, secret);
    expect(tester.state<EditableTextState>(secureEditable).copyEnabled, false);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS multiline field stays in the Flutter scene', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveTextArea(
            controller: controller,
            placeholder: 'Domain',
            minLines: 2,
            maxLines: 6,
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    await tester.enterText(find.byType(CupertinoTextField), 'SI100B_2026');
    expect(controller.text, 'SI100B_2026');
    debugDefaultTargetPlatformOverride = null;
  });
}
