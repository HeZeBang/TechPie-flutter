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

void main() {
  for (final changedScope in ['account', 'binding']) {
    testWidgets('rename updates search and export snapshots redact on $changedScope switch',
        (tester) async {
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
      // Draft rename chrome is a plain Dialog (not Material's AlertDialog).
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
      await send('Continue the original study notes');
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

      await choose(renamed, '导出 Markdown');
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

  testWidgets('a reused history row cannot export a different conversation', (tester) async {
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

    await send('First exportable conversation');
    final firstId = demo.workspace.groupId;
    demo.workspace.newConversation();
    await send('Second exportable conversation');
    final secondId = demo.workspace.groupId;
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
    final item = ValueNotifier(
      GenAiConversationSummary(
        id: firstId,
        title: 'First exportable conversation',
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
    await tester.tap(find.text('导出 Markdown'));
    await tester.pumpAndSettle();
    final snapshot = tester
        .widget<SelectableText>(
          find.descendant(
            of: find.byType(GenAiDialogFrame),
            matching: find.byType(SelectableText),
          ),
        )
        .data!;
    expect(snapshot, contains('First exportable conversation'));
    expect(snapshot, isNot(contains('Second exportable conversation')));

    // Reproduce a list refresh reusing an unkeyed row while its dialog is open.
    item.value = GenAiConversationSummary(
      id: secondId,
      title: 'Second exportable conversation',
      time: '',
    );
    await tester.pump();
    // The retained copy callback must refuse to export the stale row's text.
    await tester.tap(find.text('复制 Markdown'));
    await tester.pumpAndSettle();
    expect(copies, isEmpty);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

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
          builder: (context, child) => AdaptiveFeedbackHost(
            key: adaptiveFeedbackHostKey,
            child: child!,
          ),
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
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('导出 Markdown'), findsOneWidget);
    expect(find.text('检查同步'), findsNothing);
    expect(find.text('删除对话'), findsOneWidget);
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

  testWidgets('history menu uses the shared anchored route without covering its row',
      (tester) async {
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: GenAiConversationMenu(
                workspace: demo.workspace,
                conversation: const GenAiConversationSummary(
                  id: 'anchor-conversation',
                  title: 'Anchor conversation',
                  time: '',
                ),
                onChanged: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The default history-row host no longer builds Flutter's own popup.
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    final anchor = tester.getRect(find.byTooltip('对话操作'));
    await tester.tap(find.byTooltip('对话操作'));
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('genai-anchored-menu'));
    expect(surface, findsOneWidget);
    // Native rows, and the route sits outside the button with its 7 px gap.
    expect(
      find.descendant(
        of: surface,
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      ),
      findsNWidgets(3),
    );
    final menu = tester.getRect(surface);
    expect(menu.overlaps(anchor), isFalse);
    expect(menu.top - anchor.bottom, 7);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(surface, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header conversation menu opens 7 px below its anchor', (tester) async {
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
    final sending = demo.workspace.send('Header menu conversation');
    for (var i = 0; i < 300 && demo.workspace.sending; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await sending;
    await tester.pumpAndSettle();

    final header = find.byKey(ValueKey('genai-header-menu-${demo.workspace.groupId}'));
    expect(header, findsOneWidget);
    // The header opts into the shared exact-anchor menu, not PopupMenuButton.
    expect(
      find.descendant(of: header, matching: find.byType(PopupMenuButton<String>)),
      findsNothing,
    );

    final anchor = tester.getRect(
      find.descendant(of: header, matching: find.byTooltip('对话操作')),
    );
    await tester.tap(find.descendant(of: header, matching: find.byTooltip('对话操作')));
    await tester.pumpAndSettle();
    // Measure the painted menu surface: exactly 7 px below the anchor.
    final surface = find.byKey(const ValueKey('genai-anchored-menu'));
    expect(surface, findsOneWidget);
    expect(tester.getRect(surface).top - anchor.bottom, 7);
    expect(
      find.descendant(
        of: surface,
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      ),
      findsNWidgets(4),
    );
    expect(find.text('重命名'), findsOneWidget);
    // The native row still pops with its value, so the existing callback runs.
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-rename-input')), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename dialog uses the draft chrome and keeps the 120 cap', (tester) async {
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenAiConversationMenu(
            workspace: demo.workspace,
            conversation: const GenAiConversationSummary(
              id: 'rename-conversation',
              title: 'Existing title',
              time: '',
            ),
            onChanged: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('对话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    // The draft dialog is a plain Dialog, not Material's AlertDialog.
    expect(find.byType(AlertDialog), findsNothing);
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    final shape = tester.widget<Dialog>(dialog).shape! as RoundedRectangleBorder;
    expect((shape.borderRadius as BorderRadius).topLeft.x, 18);
    // min(500, screen - 32): the 800 px test surface leaves room for 500.
    expect(tester.getRect(find.byKey(const ValueKey('genai-rename-dialog'))).width, 500);
    // Ruled header with a title and a closing X.
    expect(find.descendant(of: dialog, matching: find.text('重命名对话')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.byTooltip('关闭')), findsOneWidget);

    // Plain soft field: no floating label, helper or counter.
    final input = find.byKey(const ValueKey('genai-rename-input'));
    final field = tester.widget<TextField>(input);
    expect(field.maxLength, 120);
    expect(field.decoration!.labelText, isNull);
    expect(field.decoration!.helperText, isNull);
    expect(field.decoration!.counterText, '');
    expect(field.decoration!.filled, isTrue);

    // Draft footer: cancel plus the primary save.
    expect(
      find.descendant(of: dialog, matching: find.widgetWithText(TextButton, '取消')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.widgetWithText(FilledButton, '保存')),
      findsOneWidget,
    );

    // 120 remains the hard cap.
    await tester.enterText(input, 'x' * 121);
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text.length, 120);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: dialog, matching: find.widgetWithText(FilledButton, '保存')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
