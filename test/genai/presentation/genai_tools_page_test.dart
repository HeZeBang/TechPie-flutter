import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/presentation/genai_tools_page.dart';

void main() {
  testWidgets('aspect ratio filters resolutions and validates linked and freeform custom sizes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo = await GenAiDemo.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(
          workspace: demo.workspace,
          demo: true,
          initialTab: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('genai-image-prompt')),
      'synthetic sizing check',
    );

    Future<void> select(String key, String label) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(label).last);
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    DropdownButton<String> dropdown(String key) => tester.widget<DropdownButton<String>>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(DropdownButton<String>),
          ),
        );
    expect(
      dropdown('genai-image-resolution').items!.map((item) => item.value),
      ['1K', '2K', 'custom'],
    );
    await select('genai-image-orientation', '横向');
    expect(
      dropdown('genai-image-resolution').items!.map((item) => item.value),
      ['1K', '2K', '4K', 'custom'],
    );
    final direction = find.byKey(const ValueKey('genai-image-orientation'));
    final ratio = find.byKey(const ValueKey('genai-image-ratio'));
    final resolution = find.byKey(const ValueKey('genai-image-resolution'));
    final quality = find.byKey(const ValueKey('genai-image-quality'));
    expect(tester.getTopLeft(direction).dy, tester.getTopLeft(ratio).dy);
    expect(tester.getTopLeft(resolution).dy, tester.getTopLeft(quality).dy);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final scenario in [(320.0, 1.0), (390.0, 1.6), (1440.0, 1.0)]) {
      tester.view.physicalSize = Size(scenario.$1, 900);
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
      await tester.pumpAndSettle();
      await tester.ensureVisible(ratio);
      expect(dropdown('genai-image-ratio').value, '16:9');
      expect(tester.getRect(ratio).right, lessThanOrEqualTo(scenario.$1));
      if (scenario.$2 > 1) {
        expect(tester.getTopLeft(ratio).dy, greaterThan(tester.getTopLeft(direction).dy));
      } else {
        expect(tester.getTopLeft(direction).dy, tester.getTopLeft(ratio).dy);
      }
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(390, 900);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpAndSettle();
    await select('genai-image-resolution', '4K · 3840 × 2160');
    expect(find.text('超2K分辨率属实验性质，效果可能不稳定。'), findsOneWidget);
    await select('genai-image-orientation', '竖向');
    expect(dropdown('genai-image-ratio').value, '9:16');
    expect(dropdown('genai-image-resolution').value, '4K');
    expect(
      dropdown('genai-image-ratio').items!.map((item) => item.value),
      ['2:3', '3:4', '4:5', '9:16', '1:2', '9:21'],
    );
    await select('genai-image-orientation', '横向');
    expect(dropdown('genai-image-ratio').value, '16:9');
    expect(dropdown('genai-image-resolution').value, '4K');
    await select('genai-image-orientation', '正方形');
    expect(dropdown('genai-image-resolution').value, '1K');
    await select('genai-image-orientation', '横向');
    await select('genai-image-resolution', '自定义分辨率');
    final width = find.byKey(const ValueKey('genai-image-width'));
    final height = find.byKey(const ValueKey('genai-image-height'));
    await tester.ensureVisible(width);
    await tester.enterText(width, '1600');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(height).controller!.text, '900');
    await tester.enterText(height, '1080');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(width).controller!.text, '1920');
    await select('genai-image-orientation', '竖向');
    expect(dropdown('genai-image-resolution').value, 'custom');
    expect(tester.widget<TextField>(width).controller!.text, '1080');
    expect(tester.widget<TextField>(height).controller!.text, '1920');
    await select('genai-image-orientation', '横向');
    expect(tester.widget<TextField>(width).controller!.text, '1920');
    expect(tester.widget<TextField>(height).controller!.text, '1080');
    await select('genai-image-orientation', '自定义');
    await tester.ensureVisible(width);
    await tester.enterText(width, '800abc');
    await tester.enterText(height, '820');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(width).controller!.text, '800');
    final generate = find.byKey(const ValueKey('genai-image-generate'));
    expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);
    await tester.enterText(height, '100');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(generate).onPressed, isNull);
    await tester.enterText(height, '820');
    await tester.pumpAndSettle();
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.textContaining('800x820'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      (await demo.workspace.repository.listImages(GenAiCancellation())).records,
      isEmpty,
    );
  });

  testWidgets('tools browse history, require image confirmation, and show usage', (tester) async {
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
    await tester.tap(find.byTooltip('对话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除对话'));
    await tester.pumpAndSettle();
    expect(find.text('这将删除此对话的本机和学校记录，无法撤销。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      (await demo.workspace.repository.listConversations(GenAiCancellation())).records,
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
    expect(find.textContaining('本地演示使用校园测试图片'), findsOneWidget);
    expect(
      (await demo.workspace.repository.listImages(GenAiCancellation())).records,
      isEmpty,
    );
    await tester.tap(find.text('开始生成'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('图片历史'));
    await tester.pumpAndSettle();
    expect(find.text('本地测试图片'), findsOneWidget);
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

  testWidgets('session search filters in real time with debounce and clear', (tester) async {
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
