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

  testWidgets('session search filters in real time with debounce and clear',
      (tester) async {
    final demo = await GenAiDemo.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();

    // Create conversation 1
    final sending1 = demo.workspace.send('quantum algorithms intro');
    for (var i = 0; i < 300 && demo.workspace.sending; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await sending1;

    // Start a new conversation and send conversation 2
    demo.workspace.newConversation();
    final sending2 = demo.workspace.send('lunch menu recommendation');
    for (var i = 0; i < 300 && demo.workspace.sending; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await sending2;

    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(workspace: demo.workspace, demo: true),
      ),
    );
    await tester.pumpAndSettle();

    // Both should be visible initially
    expect(find.text('quantum algorithms intro'), findsOneWidget);
    expect(find.text('lunch menu recommendation'), findsOneWidget);

    // Type query without pressing Enter (realtime search)
    final searchField = find.widgetWithText(TextField, '搜索对话');
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'quantum');
    await tester.pump();

    // Clear icon should be visible immediately since text is non-empty
    expect(find.byTooltip('清除'), findsOneWidget);

    // Wait for debounce (250ms) to trigger and settle
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Now filtered in real time
    expect(find.text('quantum algorithms intro'), findsOneWidget);
    expect(find.text('lunch menu recommendation'), findsNothing);

    // Enter a query with no matches
    await tester.enterText(searchField, 'nonexistent query 12345');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('quantum algorithms intro'), findsNothing);
    expect(find.text('lunch menu recommendation'), findsNothing);
    expect(find.text('未找到与「nonexistent query 12345」相关的会话'), findsOneWidget);
    expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);

    // Tap clear button
    await tester.tap(find.byTooltip('清除'));
    await tester.pumpAndSettle();

    // Search reset: both conversations restored
    expect(find.text('quantum algorithms intro'), findsOneWidget);
    expect(find.text('lunch menu recommendation'), findsOneWidget);
    expect(find.byTooltip('清除'), findsNothing);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
