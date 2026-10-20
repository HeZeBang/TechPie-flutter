import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/presentation/genai_tools_page.dart';

void main() {
  testWidgets(
      'tools browse history, require image confirmation, and show usage',
      (tester) async {
    final demo = await GenAiDemo.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    final sending = demo.workspace.send('saved test');
    for (var i = 0; i < 300 && demo.workspace.sending; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await sending;
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(workspace: demo.workspace, demo: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('saved test'), findsOneWidget);
    await tester.tap(find.byTooltip('删除对话'));
    await tester.pumpAndSettle();
    expect(find.text('这将删除学校平台上的记录，无法撤销。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      (await demo.workspace.repository.listConversations(GenAiCancellation()))
          .records,
      hasLength(1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(
          key: const ValueKey('images'),
          workspace: demo.workspace,
          demo: true,
          initialTab: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('genai-image-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('图片创作 · 演示').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('genai-image-prompt')),
      'a blue pie',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('生成 1 张图片'));
    await tester.tap(find.text('生成 1 张图片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('可能扣除学校账号额度'), findsOneWidget);
    expect(
      (await demo.workspace.repository.listImages(GenAiCancellation())).records,
      isEmpty,
    );
    await tester.tap(find.text('开始生成'));
    await tester.pumpAndSettle();
    expect(find.text('本次生成'), findsOneWidget);
    expect(find.text('本地图片预览 · 演示'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(
          key: const ValueKey('usage'),
          workspace: demo.workspace,
          demo: true,
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('免费额度'), findsOneWidget);
    expect(find.textContaining('剩余 35'), findsOneWidget);
    await demo.sessions.setOwner(null);
    await tester.pumpAndSettle();
    expect(find.text('免费额度'), findsNothing);
    expect(find.textContaining('账号已切换'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
