import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_text_area.dart';
import 'package:techpie/widgets/adaptive_text_field_group.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets(
      'iOS grouped fields use Flutter text input and update controllers', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
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
    expect(find.byType(CupertinoTextField), findsNWidgets(2));
    await tester.enterText(find.byType(CupertinoTextField).first, '20260001');
    expect(account.text, '20260001');
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
