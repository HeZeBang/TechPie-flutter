import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/presentation/genai_conversation_menu.dart';
import 'package:techpie/features/genai/presentation/genai_tools_page.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

void main() {
  for (final changedScope in ['account', 'binding']) {
    testWidgets('rename updates search and export snapshots redact on $changedScope switch',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
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

      Future<void> send(String prompt) async {
        final pending = demo.workspace.send(prompt);
        for (var i = 0; i < 300 && demo.workspace.sending; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await pending;
      }

      await send(original);
      final originalId = demo.workspace.groupId;
      demo.workspace.newConversation();
      await send(other);
      final copies = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copies.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: GenAiToolsPage(workspace: demo.workspace),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(original), findsOneWidget);
      expect(find.text(other), findsOneWidget);

      Future<void> choose(String title, String action) async {
        final row = find.ancestor(
          of: find.text(title),
          matching: find.byType(ListTile),
        );
        await tester.tap(find.descendant(of: row, matching: find.byTooltip('对话操作')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
      }

      await choose(original, '重命名');
      final renameInput = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(renameInput, renamed);
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text(renamed), findsOneWidget);
      expect(find.text(original), findsNothing);
      // A title is synced by the next ordinary exchange, not a hidden model call.
      await demo.workspace.openConversation(originalId, GenAiCancellation());
      await send('Continue the original study notes');
      final search = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '搜索对话',
      );
      await tester.enterText(search, renamed);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text(renamed), findsNWidgets(2));
      expect(find.text(other), findsNothing);

      // Choose the list-row title rather than the matching search field text.
      final renamedRow = find.byType(ListTile);
      await tester.tap(
        find.descendant(of: renamedRow, matching: find.byTooltip('对话操作')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出对话'));
      await tester.pumpAndSettle();
      final snapshot = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(snapshot, startsWith('# $renamed\n'));
      expect(snapshot, contains(original));
      expect(snapshot, isNot(contains(other)));
      expect(snapshot, isNot(contains('techpie-agent-call')));
      await tester.tap(find.text('复制 Markdown'));
      await tester.pumpAndSettle();
      expect(copies, [snapshot]);

      final copyBeforeRebuild = tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('复制 Markdown'),
              matching: find.byWidgetPredicate((widget) => widget is FilledButton),
            ),
          )
          .onPressed!;
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
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('复制 Markdown'),
                matching: find.byWidgetPredicate((widget) => widget is FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.textContaining(renamed), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('a reused history row cannot rename a different conversation', (tester) async {
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    Future<void> send(String prompt) async {
      final pending = demo.workspace.send(prompt);
      for (var i = 0; i < 300 && demo.workspace.sending; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await pending;
    }

    await send('First saved conversation');
    final firstId = demo.workspace.groupId;
    demo.workspace.newConversation();
    await send('Second saved conversation');
    final secondId = demo.workspace.groupId;
    final item = ValueNotifier(
      GenAiConversationSummary(
        id: firstId,
        title: 'First saved conversation',
        time: '',
      ),
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
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'A title intended only for the first row',
    );
    await tester.pump();
    // Reproduce a list refresh reusing an unkeyed row while its modal is open.
    item.value = GenAiConversationSummary(
      id: secondId,
      title: 'Second saved conversation',
      time: '',
    );
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final firstRead = demo.workspace.conversationForExport(firstId, GenAiCancellation());
    final secondRead = demo.workspace.conversationForExport(secondId, GenAiCancellation());
    await tester.pumpAndSettle();
    expect((await firstRead).title, 'First saved conversation');
    expect((await secondRead).title, 'Second saved conversation');
    expect(tester.takeException(), isNull);
  });
}
