import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/genai_turn_edit_dialog.dart';

GenAiTurnEditDialog _dialog({
  String prompt = 'original message',
  String action = 'edit',
  bool hasAttachments = false,
  bool hasExternalActions = false,
  Future<void> Function(String, VoidCallback)? onSubmit,
}) => GenAiTurnEditDialog(
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
                  ? Navigator.of(
                      context,
                    ).push<void>(MaterialPageRoute(builder: (_) => Scaffold(body: dialog)))
                  : genAiShowDialog<void>(context: context, builder: (_) => dialog),
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

  testWidgets('editing warns about retained attachments and external actions when applicable', (
    tester,
  ) async {
    for (final attached in [false, true]) {
      for (final external in [false, true]) {
        await _pump(tester, _dialog(hasAttachments: attached, hasExternalActions: external));
        expect(find.textContaining('之后的回答将被替换'), findsOneWidget);
        expect(find.textContaining('原附件会保留'), attached ? findsOneWidget : findsNothing);
        expect(find.textContaining('不会撤销已提交'), external ? findsOneWidget : findsNothing);
      }
    }
  });

  testWidgets('deletion explains the permanent change and can be dismissed on a phone', (
    tester,
  ) async {
    await _pump(tester, _dialog(action: 'delete'), size: const Size(375, 812));
    expect(find.textContaining('将永久删除 1 轮对话及其工具记录'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认').hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('genai-turn-dialog-close')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets('edit submission sends the replacement text and closes', (tester) async {
    String? submitted;
    await _pump(
      tester,
      _dialog(
        prompt: '',
        onSubmit: (value, commit) async {
          submitted = value;
          commit();
        },
      ),
    );

    final primary = find.widgetWithText(FilledButton, '保存并重发');
    expect(tester.widget<FilledButton>(primary).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'replacement');
    await tester.pump();
    await tester.tap(primary);
    await tester.pumpAndSettle();

    expect(submitted, 'replacement');
    expect(find.byKey(const ValueKey('genai-inline-edit')), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });
}
