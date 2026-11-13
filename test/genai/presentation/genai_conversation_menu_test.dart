import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/presentation/genai_conversation_menu.dart';
import 'package:techpie/features/genai/presentation/genai_history_sidebar.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

Future<String> _send(WidgetTester tester, TestGenAiWorkspace demo, String prompt) async {
  final sending = demo.workspace.send(prompt);
  for (var i = 0; i < 300 && demo.workspace.sending; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await sending;
  return demo.workspace.groupId;
}

List<String> _captureCopies() {
  final copies = <String>[];
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copies.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copies;
}

void main() {
  for (final changedScope in ['account', 'binding']) {
    testWidgets('rename updates search and export snapshots redact on $changedScope switch', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final binding = ValueNotifier('binding-a');
      addTearDown(binding.dispose);
      final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
      addTearDown(demo.dispose);
      demo.workspace.configureAgent(
        runner: GenAiAgentRunner(
          tools: () => GenAiAgentToolRegistry(const []),
          streamChat: demo.workspace.repository.streamChat,
        ),
        scope: () => binding.value,
        scopeChanges: binding,
      );
      await demo.workspace.reloadModels();
      const original = 'Private original assignment question';
      const renamed = 'Renamed personal study notes';
      const other = 'Unrelated second conversation';

      final originalId = await _send(tester, demo, original);
      demo.workspace.newConversation();
      await _send(tester, demo, other);
      final copies = _captureCopies();

      demo.workspace.newConversation();
      await tester.pumpWidget(
        MaterialApp(
          home: GenAiWorkspace(controller: demo.workspace, login: (_) async => null),
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byType(GenAiHistorySidebar);
      Finder inSidebar(Finder finder) => find.descendant(of: sidebar, matching: finder);
      expect(inSidebar(find.text(original)), findsOneWidget);
      expect(inSidebar(find.text(other)), findsOneWidget);

      Future<void> choose(String title, String action) async {
        final row = find.ancestor(of: inSidebar(find.text(title)), matching: find.byType(InkWell));
        await tester.tap(find.descendant(of: row.first, matching: find.byTooltip('对话操作')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
      }

      await choose(original, '重命名');
      final renameInput = find.byKey(const ValueKey('genai-rename-input'));
      expect(renameInput, findsOneWidget);
      await tester.enterText(renameInput, renamed);
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(inSidebar(find.text(renamed)), findsOneWidget);
      expect(inSidebar(find.text(original)), findsNothing);
      // A title is synced by the next ordinary exchange, not a hidden model call.
      await demo.workspace.openConversation(originalId, GenAiCancellation());
      await _send(tester, demo, 'Continue the original study notes');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索对话'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('genai-search-input'));
      await tester.enterText(search, renamed);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      // The draft result row carries the renamed title and its stable id.
      expect(find.byKey(ValueKey('genai-search-result-$originalId')), findsOneWidget);
      expect(find.text(other), findsNothing);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      await choose(renamed, '导出对话');
      final snapshot = tester
          .widget<SelectableText>(
            find.descendant(
              of: find.byType(GenAiDialogFrame),
              matching: find.byType(SelectableText),
            ),
          )
          .data!;
      expect(snapshot, startsWith('# $renamed\n'));
      expect(snapshot, contains(original));
      expect(snapshot, isNot(contains(other)));
      expect(snapshot, isNot(contains('techpie-agent-call')));
      await tester.tap(find.text('复制 Markdown'));
      await tester.pumpAndSettle();
      expect(copies, [snapshot]);

      final copy = find.widgetWithText(FilledButton, '复制 Markdown');
      final copyBeforeRebuild = tester.widget<FilledButton>(copy).onPressed!;
      if (changedScope == 'account') {
        await demo.sessions.setOwner(ownerB);
      } else {
        binding.value = 'binding-b';
      }
      // Exercise a callback retained from the old frame, before the disabled
      // button is rebuilt. Its own scope guard must prevent clipboard leakage.
      copyBeforeRebuild();
      await tester.pumpAndSettle();
      expect(copies, [snapshot]);
      expect(find.text('对话或账号已切换，请重新打开导出。'), findsOneWidget);
      expect(find.textContaining(original), findsNothing);
      expect(tester.widget<FilledButton>(copy).onPressed, isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      // The open chat and its search are always reset. A binding change keeps
      // the same GenAI account, so the sidebar reloads that account's list;
      // only another account must not see the renamed conversation at all.
      expect(find.byKey(const ValueKey('genai-thread')), findsNothing);
      if (changedScope == 'account') {
        expect(find.textContaining(renamed), findsNothing);
      } else {
        await tester.tap(find.byTooltip('搜索对话'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final action in ['重命名', '导出对话']) {
    testWidgets('a reused history row cannot apply $action to a different conversation', (
      tester,
    ) async {
      final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
      addTearDown(demo.dispose);
      await demo.workspace.reloadModels();
      final firstId = await _send(tester, demo, 'First saved conversation');
      demo.workspace.newConversation();
      final secondId = await _send(tester, demo, 'Second saved conversation');
      final copies = action == '导出对话' ? _captureCopies() : <String>[];
      final item = ValueNotifier(
        GenAiConversationSummary(id: firstId, title: 'First saved conversation', time: ''),
      );
      addTearDown(item.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<GenAiConversationSummary>(
              valueListenable: item,
              builder: (_, conversation, __) => GenAiConversationMenu(
                workspace: demo.workspace,
                conversation: conversation,
                onChanged: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('对话操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      if (action == '重命名') {
        await tester.enterText(find.byType(TextField), 'A title intended only for the first row');
        await tester.pump();
      } else {
        final snapshot = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
        expect(snapshot, contains('First saved conversation'));
        expect(snapshot, isNot(contains('Second saved conversation')));
      }
      // Reproduce a list refresh reusing an unkeyed row while its modal is open.
      item.value = GenAiConversationSummary(
        id: secondId,
        title: 'Second saved conversation',
        time: '',
      );
      await tester.pump();
      if (action == '重命名') {
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        final firstRead = demo.workspace.conversationForExport(firstId, GenAiCancellation());
        final secondRead = demo.workspace.conversationForExport(secondId, GenAiCancellation());
        await tester.pumpAndSettle();
        expect((await firstRead).title, 'First saved conversation');
        expect((await secondRead).title, 'Second saved conversation');
      } else {
        await tester.tap(find.text('复制 Markdown'));
        await tester.pumpAndSettle();
        expect(copies, isEmpty);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('check sync is opt-in and reports a guarded refresh', (tester) async {
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    final sending = demo.workspace.send('Saved conversation');
    await tester.pumpAndSettle();
    await sending;
    final conversation = GenAiConversationSummary(
      id: demo.workspace.groupId,
      title: 'Saved conversation',
      time: '',
    );

    Future<void> show({required bool showSync}) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AdaptiveFeedbackHost(key: adaptiveFeedbackHostKey, child: child!),
          home: Scaffold(
            body: GenAiConversationMenu(
              workspace: demo.workspace,
              conversation: conversation,
              onChanged: () {},
              onDelete: () {},
              showSync: showSync,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(showSync: false);
    await tester.tap(find.byTooltip('对话操作'));
    await tester.pumpAndSettle();
    expect(find.text('检查同步'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await show(showSync: true);
    await tester.tap(find.byTooltip('对话操作'));
    await tester.pumpAndSettle();
    expect(find.text('检查同步'), findsOneWidget);
    await tester.tap(find.text('检查同步'));
    await tester.pumpAndSettle();
    expect(find.text('已检查同步'), findsOneWidget);
    expect(demo.workspace.archiveFailure, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop header menu can rename a conversation beyond the old title cap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiWorkspace(controller: demo.workspace, login: (_) async => null),
      ),
    );
    await tester.pumpAndSettle();
    await _send(tester, demo, 'Header menu conversation');
    await tester.pumpAndSettle();

    final header = find.byKey(ValueKey('genai-header-menu-${demo.workspace.groupId}'));
    expect(header, findsOneWidget);
    await tester.tap(find.descendant(of: header, matching: find.byTooltip('对话操作')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('genai-rename-input'));
    final title = 'x' * 121;
    await tester.enterText(input, title);
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(input, findsNothing);
    expect(find.text(title), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
