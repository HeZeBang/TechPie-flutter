import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/presentation/genai_thinking_view.dart';
import 'package:techpie/features/genai/presentation/genai_web_search_view.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';

import '../support/fakes.dart';

void main() {
  Future<GenAiDemo> show(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    bool connected = true,
    double scale = 1,
    double keyboard = 0,
    Duration delay = const Duration(milliseconds: 1),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo =
        await GenAiDemo.create(connected: connected, chunkDelay: delay);
    addTearDown(demo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: GenAiWorkspace(
          controller: demo.workspace,
          demo: true,
          login: (_) async =>
              const GenAiCredential(token: DemoGenAiBackend.token),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return demo;
  }

  testWidgets(
      'wide workspace has no suggested prompts and sends typed Markdown chat',
      (tester) async {
    final demo = await show(tester);
    expect(find.text('TechPie'), findsOneWidget);
    expect(find.text('本地演示 · 不访问校园服务，不产生费用'), findsOneWidget);
    expect(find.text('理清学习思路'), findsNothing);
    expect(find.text('一起写段代码'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '帮我制定学习计划',
    );
    await tester.pump();
    expect(demo.workspace.turns, isEmpty);
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();
    expect(demo.workspace.turns.single.phase, GenAiChatPhase.completed);
    expect(find.byKey(const ValueKey('genai-copy-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'demo login connects without campus requests and logout clears the conversation',
      (tester) async {
    final demo = await show(tester, connected: false);
    expect(find.text('连接你的校园 AI'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('genai-connect')));
    await tester.pumpAndSettle();
    expect(demo.workspace.connected, isTrue);
    expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);
    await tester.tap(find.byTooltip('GenAI 账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('断开 GenAI'));
    await tester.pumpAndSettle();
    expect(find.text('连接你的校园 AI'), findsOneWidget);
    expect(demo.sessions.session, isNull);
  });

  testWidgets('bound IDS without a school ID offers identity resolution',
      (tester) async {
    final demo = await GenAiDemo.create(connected: false);
    addTearDown(demo.dispose);
    await demo.sessions.setOwner(null);
    var connects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiWorkspace(
          controller: demo.workspace,
          campusBound: true,
          login: (_) async => throw StateError('manual login must not run'),
          onPreviewLiveLogin: () => connects++,
          onBindCampus: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('校园身份待同步'), findsOneWidget);
    expect(find.text('绑定校园账号'), findsNothing);
    expect(find.text('管理校园账号'), findsOneWidget);
    await tester.tap(find.text('使用现有 IDS 会话连接'));
    await tester.pump();
    expect(connects, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialogue and image sit beside new chat and usage is in account',
      (tester) async {
    await show(tester, size: const Size(674, 1000));
    expect(find.text('更多功能'), findsNothing);
    final fresh = tester.getCenter(find.byTooltip('新的对话'));
    final history = tester.getCenter(find.byTooltip('会话记录'));
    final image = tester.getCenter(find.byTooltip('图片创作'));
    expect(fresh.dy, history.dy);
    expect(history.dy, image.dy);
    expect(fresh.dx, lessThan(history.dx));
    expect(history.dx, lessThan(image.dx));
    expect(find.text('用量统计'), findsNothing);
    await tester.tap(find.byTooltip('会话记录'));
    await tester.pumpAndSettle();
    expect(find.text('搜索对话'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('图片创作'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-image-prompt')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('GenAI 账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用量统计'));
    await tester.pumpAndSettle();
    expect(find.text('免费额度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop preserves partial output and exposes an explicit retry',
      (tester) async {
    final demo = await show(tester, delay: const Duration(milliseconds: 20));
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      'test stop',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();
    expect(demo.workspace.turns.single.phase, GenAiChatPhase.cancelled);
    expect(demo.workspace.turns.single.answer, isNotEmpty);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('narrow screen with large text and keyboard has no overflow',
      (tester) async {
    await show(tester, size: const Size(320, 740), scale: 1.6, keyboard: 280);
    expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new conversation and account switch remove drafts and previous output',
      (tester) async {
    final demo = await show(tester);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      'private draft',
    );
    await demo.sessions.setOwner(ownerB);
    await tester.pumpAndSettle();
    expect(find.text('private draft'), findsNothing);
    expect(find.byKey(const ValueKey('genai-prompt')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IME composition and Shift Enter do not submit a message',
      (tester) async {
    final demo = await show(tester);
    final input = find.byKey(const ValueKey('genai-prompt'));
    await tester.enterText(input, 'hello');
    final controller = tester.widget<TextField>(input).controller!;
    controller.value = const TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(demo.workspace.turns, isEmpty);
    controller.value = const TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 5),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(demo.workspace.turns, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(demo.workspace.turns.length, 1);
  });

  testWidgets('toggle thinking and net search chips updates controller state',
      (tester) async {
    final demo = await show(tester);
    final thinkingChip = find.byKey(const ValueKey('genai-thinking-toggle'));
    final searchChip = find.byKey(const ValueKey('genai-search-toggle'));
    expect(thinkingChip, findsOneWidget);
    expect(searchChip, findsOneWidget);

    expect(demo.workspace.thinkingEnabled, isFalse);
    await tester.tap(thinkingChip);
    await tester.pump();
    expect(demo.workspace.thinkingEnabled, isTrue);

    expect(demo.workspace.netSearchEnabled, isFalse);
    await tester.tap(searchChip);
    await tester.pump();
    expect(demo.workspace.netSearchEnabled, isTrue);
  });

  testWidgets(
      'chat with thinking and net search renders thinking and search views',
      (tester) async {
    final demo = await show(tester);
    await tester.tap(find.byKey(const ValueKey('genai-thinking-toggle')));
    await tester.tap(find.byKey(const ValueKey('genai-search-toggle')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '介绍上海科技大学',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();

    expect(demo.workspace.turns.single.phase, GenAiChatPhase.completed);
    expect(demo.workspace.turns.single.reasoning, isNotEmpty);
    expect(demo.workspace.turns.single.citations.length, 2);

    expect(find.byType(GenAiThinkingView), findsOneWidget);
    expect(find.byType(GenAiWebSearchView), findsOneWidget);
    expect(find.textContaining('已深度思考'), findsOneWidget);
    expect(find.textContaining('已检索 2 条网络参考来源'), findsOneWidget);
  });

  testWidgets('TTS voice playback button triggers without exception',
      (tester) async {
    await show(tester);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '测试语音播报',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();

    final ttsButton = find.byKey(const ValueKey('genai-tts-0'));
    expect(ttsButton, findsOneWidget);
    await tester.tap(ttsButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
