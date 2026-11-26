import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/theme/theme.dart';
import 'package:techpie/widgets/adaptive_text_area.dart';
import 'package:techpie/widgets/adaptive_text_field_group.dart';
import 'package:techpie/widgets/secure_password_field.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('secure Material input has an accessible name and masked value', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecurePasswordField(
            controller: controller,
            placeholder: 'IDS password',
          ),
        ),
      ),
    );
    final editable = find.byWidgetPredicate((widget) => widget is EditableText);
    await tester.tap(editable);
    tester.testTextInput.enterText('synthetic-secret');
    await tester.pump();
    final node = tester.getSemantics(editable);
    expect(
      node,
      matchesSemantics(
        label: 'IDS password',
        value: '•' * controller.text.length,
        isTextField: true,
        isObscured: true,
        isFocused: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        hasFocusAction: true,
        hasSetTextAction: true,
        hasSetSelectionAction: true,
        hasTapAction: true,
        hasMoveCursorBackwardByCharacterAction: true,
        hasMoveCursorBackwardByWordAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('iOS grouped fields use Flutter text input and update controllers', (
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

  testWidgets('iOS AdaptiveTextFieldGroup & AdaptiveTextArea distinguish surface fill on canvas vs embedded', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final areaCtrl = TextEditingController();
    addTearDown(() {
      c1.dispose();
      c2.dispose();
      areaCtrl.dispose();
    });

    final tp = TpColors.light();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: tp.toColorScheme(),
      extensions: [tp],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          backgroundColor: tp.canvas,
          body: Column(
            children: [
              AdaptiveTextFieldGroup(
                key: const Key('group-canvas'),
                items: [AdaptiveTextFieldGroupItem(controller: c1, placeholder: 'Canvas')],
              ),
              AdaptiveTextFieldGroup(
                key: const Key('group-embedded'),
                embedded: true,
                items: [AdaptiveTextFieldGroupItem(controller: c2, placeholder: 'Embedded')],
              ),
              AdaptiveTextArea(
                key: const Key('area-canvas'),
                controller: areaCtrl,
                placeholder: 'Area',
              ),
            ],
          ),
        ),
      ),
    );

    BoxDecoration? fillDecorationFor(Key key) {
      final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(of: find.byKey(key), matching: find.byType(DecoratedBox)),
      );
      for (final box in boxes) {
        final dec = box.decoration;
        if (dec is BoxDecoration && dec.color != null) return dec;
      }
      return null;
    }

    BoxDecoration? borderDecorationFor(Key key) {
      final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(of: find.byKey(key), matching: find.byType(DecoratedBox)),
      );
      for (final box in boxes) {
        final dec = box.decoration;
        if (dec is BoxDecoration && dec.border != null) return dec;
      }
      return null;
    }

    expect(fillDecorationFor(const Key('group-canvas'))?.color, tp.surface);
    expect(fillDecorationFor(const Key('group-canvas'))?.color, isNot(tp.canvas));
    expect(borderDecorationFor(const Key('group-canvas'))?.border, isNotNull);
    expect(fillDecorationFor(const Key('group-embedded'))?.color, tp.surfaceSubtle);

    final areaField = tester.widget<CupertinoTextField>(
      find.descendant(
        of: find.byKey(const Key('area-canvas')),
        matching: find.byType(CupertinoTextField),
      ),
    );
    expect(areaField.decoration?.color, tp.surface);
    expect(areaField.decoration?.border, isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS AdaptiveTextFieldGroup Next advances to immediate next field without skipping', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final c3 = TextEditingController();
    addTearDown(() {
      c1.dispose();
      c2.dispose();
      c3.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveTextFieldGroup(
            items: [
              AdaptiveTextFieldGroupItem(
                controller: c1,
                placeholder: 'First',
                textInputAction: TextInputAction.next,
              ),
              AdaptiveTextFieldGroupItem(
                controller: c2,
                placeholder: 'Second',
                textInputAction: TextInputAction.next,
              ),
              AdaptiveTextFieldGroupItem(
                controller: c3,
                placeholder: 'Third',
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
      ),
    );

    final editables = find.byType(EditableText);
    await tester.tap(editables.at(0));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(tester.widget<EditableText>(editables.at(1)).focusNode.hasFocus, isTrue);
    expect(tester.widget<EditableText>(editables.at(2)).focusNode.hasFocus, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
