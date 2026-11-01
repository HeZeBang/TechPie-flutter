import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/genai_turn_edit_dialog.dart';

const _dialogKey = ValueKey('genai-turn-dialog');
const _headerKey = ValueKey('genai-turn-dialog-header');
const _bodyKey = ValueKey('genai-turn-dialog-body');
const _footerKey = ValueKey('genai-turn-dialog-footer');
const _warningKey = ValueKey('genai-turn-dialog-warning');
const _closeKey = ValueKey('genai-turn-dialog-close');

GenAiTurnEditDialog _dialog({
  String prompt = 'original message',
  String action = 'edit',
  bool hasAttachments = false,
  bool hasExternalActions = false,
  bool hasComposerDraft = false,
  Future<void> Function(String, VoidCallback)? onSubmit,
}) =>
    GenAiTurnEditDialog(
      prompt: prompt,
      action: action,
      removedTurns: 1,
      hasAttachments: hasAttachments,
      hasExternalActions: hasExternalActions,
      hasComposerDraft: hasComposerDraft,
      onSubmit: onSubmit ?? (_, __) async {},
    );

Future<void> _pump(
  WidgetTester tester,
  GenAiTurnEditDialog dialog, {
  Size size = const Size(800, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Drop any dialog route from an earlier scenario before rebuilding.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => genAiShowDialog<void>(
                context: context,
                builder: (_) => dialog,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _warningText(WidgetTester tester) => tester.widget<Text>(find.byKey(_warningKey)).data!;

void main() {
  testWidgets('edit dialog uses an unpadded Dialog with the draft geometry', (tester) async {
    await _pump(tester, _dialog());

    // The custom shell replaces the default padded AlertDialog.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.getSize(find.byKey(_dialogKey)).width, 500);
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    );

    // Header: 18/22 padding, 17px title, and a 36px close X.
    final header = tester.widget<Padding>(find.byKey(_headerKey));
    expect(header.padding, const EdgeInsets.symmetric(horizontal: 22, vertical: 18));
    expect(tester.widget<Text>(find.text('编辑消息')).style?.fontSize, 17);
    expect(tester.getSize(find.byKey(_closeKey)), const Size(36, 36));
    expect(find.byType(Divider), findsOneWidget);

    // Body padding and a textarea at least 120px tall with the draft field
    // treatment: 12px padding, radius 9, soft background and 1.5 line height.
    final body = tester.widget<SingleChildScrollView>(find.byKey(_bodyKey));
    expect(body.padding, const EdgeInsets.all(24));
    expect(tester.getSize(find.byType(TextField)).height, greaterThanOrEqualTo(120));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.height, 1.5);
    final decoration = field.decoration!;
    expect(decoration.filled, isTrue);
    expect(decoration.contentPadding, const EdgeInsets.all(12));
    expect(
      decoration.fillColor,
      Theme.of(tester.element(find.byType(TextField))).colorScheme.surfaceContainerHigh,
    );
    expect(
      (decoration.border! as OutlineInputBorder).borderRadius,
      BorderRadius.circular(9),
    );
    // The warning follows the textarea with a 12px top margin.
    expect(
      tester.getRect(find.byKey(_warningKey)).top - tester.getRect(find.byType(TextField)).bottom,
      closeTo(12, 0.01),
    );

    // Footer padding, 9px gap and the edit-specific primary label.
    final footer = tester.widget<Padding>(find.byKey(_footerKey));
    expect(footer.padding, const EdgeInsets.fromLTRB(24, 0, 24, 22));
    final cancel = tester.getRect(find.widgetWithText(TextButton, '取消'));
    final primary = tester.getRect(find.widgetWithText(FilledButton, '保存并重发'));
    expect(primary.left - cancel.right, closeTo(9, 0.01));

    expect(find.text('这条消息及之后的回答将被替换。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog width shrinks to the screen minus 32 on narrow screens', (tester) async {
    await _pump(tester, _dialog(), size: const Size(375, 812));

    expect(tester.getSize(find.byKey(_dialogKey)).width, 375 - 32);
    expect(tester.takeException(), isNull);
  });

  testWidgets('warning clauses are independent and stay one short paragraph', (tester) async {
    await _pump(tester, _dialog());
    expect(_warningText(tester), '这条消息及之后的回答将被替换。');
    expect(find.textContaining('原附件'), findsNothing);
    expect(find.textContaining('预约或图片任务'), findsNothing);

    // Attachment alone, no external outcome.
    await _pump(tester, _dialog(hasAttachments: true));
    expect(
      _warningText(tester),
      '这条消息及之后的回答将被替换。原附件会保留并随新消息重新发送。',
    );
    expect(find.textContaining('预约或图片任务'), findsNothing);

    // External outcome alone, no attachments.
    await _pump(tester, _dialog(hasExternalActions: true));
    expect(
      _warningText(tester),
      '这条消息及之后的回答将被替换。删除记录不会撤销已提交的预约或图片任务。',
    );
    expect(find.textContaining('原附件'), findsNothing);

    // Both clauses, still a single paragraph.
    await _pump(tester, _dialog(hasAttachments: true, hasExternalActions: true));
    expect(
      _warningText(tester),
      '这条消息及之后的回答将被替换。'
      '原附件会保留并随新消息重新发送。'
      '删除记录不会撤销已提交的预约或图片任务。',
    );

    // The composer-draft input stays accepted for callers but no longer
    // lengthens the warning.
    await _pump(tester, _dialog(hasComposerDraft: true));
    expect(_warningText(tester), '这条消息及之后的回答将被替换。');
  });

  testWidgets('delete and revert keep their own warning and confirmation label', (tester) async {
    await _pump(tester, _dialog(action: 'delete'));

    expect(find.text('删除此轮及后续'), findsOneWidget);
    expect(find.text('将永久删除 1 轮对话及其工具记录，所有设备同步生效。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认'), findsOneWidget);
  });

  testWidgets('edit submission sends the replacement text and closes', (tester) async {
    String? submitted;
    await _pump(
      tester,
      _dialog(
        onSubmit: (value, commit) async {
          submitted = value;
          commit();
        },
      ),
    );

    final primary = find.widgetWithText(FilledButton, '保存并重发');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'replacement');
    await tester.pump();
    await tester.tap(primary);
    await tester.pumpAndSettle();

    expect(submitted, 'replacement');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('empty replacement keeps the primary action disabled', (tester) async {
    await _pump(tester, _dialog(prompt: ''));

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存并重发'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('close X dismisses the dialog', (tester) async {
    await _pump(tester, _dialog());

    await tester.tap(find.byKey(_closeKey));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
