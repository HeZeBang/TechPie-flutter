import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/genai_turn_edit_dialog.dart';

const _dialogKey = ValueKey('genai-turn-dialog');
const _warningKey = ValueKey('genai-turn-dialog-warning');
const _closeKey = ValueKey('genai-turn-dialog-close');

GenAiTurnEditDialog _dialog({
  String prompt = 'original message',
  String action = 'edit',
  bool hasAttachments = false,
  bool hasExternalActions = false,
  Future<void> Function(String, VoidCallback)? onSubmit,
}) =>
    GenAiTurnEditDialog(
      prompt: prompt,
      action: action,
      removedTurns: 1,
      hasAttachments: hasAttachments,
      hasExternalActions: hasExternalActions,
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
              onPressed: () => dialog.action == 'edit'
                  ? Navigator.of(context)
                      .push<void>(MaterialPageRoute(builder: (_) => Scaffold(body: dialog)))
                  : genAiShowDialog<void>(
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
  testWidgets('an uncommitted submit keeps replacement text and permits retry', (tester) async {
    await _pump(tester, _dialog());
    await tester.enterText(find.byType(TextField), 'Keep this replacement');
    await tester.tap(find.widgetWithText(FilledButton, '保存并重发'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Keep this replacement'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存并重发')).onPressed,
      isNotNull,
    );
  });

  testWidgets('dialog width shrinks to the screen minus 32 on narrow screens', (tester) async {
    await _pump(tester, _dialog(action: 'delete'), size: const Size(375, 812));

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
    expect(find.byKey(const ValueKey('genai-inline-edit')), findsNothing);
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
    await _pump(tester, _dialog(action: 'revert'));

    await tester.tap(find.byKey(_closeKey));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
