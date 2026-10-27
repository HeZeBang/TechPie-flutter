import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker.dart';

import '../support/journal_server.dart';

void main() {
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() ready, {
    String Function()? reason,
  }) async {
    for (var i = 0; i < 120 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(ready(), isTrue, reason: reason?.call());
    await tester.pump();
  }

  Future<void> show(WidgetTester tester, GenAiWorkspaceController controller) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiWorkspace(
          controller: controller,
          demo: true,
          picker: _Picker(),
          login: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String prompt) async {
    await tester.enterText(find.byKey(const ValueKey('genai-prompt')), prompt);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
  }

  for (final action in [
    'approve',
    'reject',
    'stop',
    'account',
    'binding',
    'timeout',
    'dispose',
  ]) {
    testWidgets('main chat agent approval $action guards side effects', (tester) async {
      final server = JournalServer();
      final demo = await JournalClient.create(server);
      addTearDown(demo.dispose);
      final scope = ValueNotifier(true);
      addTearDown(scope.dispose);
      var effects = 0;
      final requests = <GenAiChatRequest>[];
      final registry = GenAiAgentToolRegistry([
        GenAiAgentTool(
          name: 'generate_image',
          description: 'Generate one test image.',
          parameters: const {
            'type': 'object',
            'properties': <String, Object?>{},
          },
          prepare: (_, context) async => GenAiAgentPreparedTool(
            requiresApproval: true,
            summary: '生成 1 张图片 · 普通质量',
            details: const {'size': '1024 × 1024', 'quota': '仅本地测试'},
            execute: () async {
              context.checkActive();
              effects++;
              return {
                'status': 'generated',
                'images': [
                  'https://genaipic.shanghaitech.edu.cn/sys/common/static/techpie-preview/image-1.png',
                ],
              };
            },
          ),
        ),
      ]);
      demo.workspace.configureAgent(
        scope: () => scope.value,
        scopeChanges: scope,
        runner: GenAiAgentRunner(
          tools: registry,
          limits: GenAiAgentLimits(
            runTimeout: action == 'timeout'
                ? const Duration(milliseconds: 200)
                : const Duration(minutes: 4),
          ),
          streamChat: (request, cancellation) {
            requests.add(request);
            return demo.repository.streamChat(request, cancellation);
          },
        ),
      );
      server.onGenerate = (body) => server.generations.length == 1
          ? server.call(body, name: 'generate_image')
          : server.finalAnswer(body, '任务已处理，请查看工具结果。');
      await show(tester, demo.workspace);
      await tester.tap(find.byKey(const ValueKey('genai-agent-toggle')));
      await tester.pump();
      await send(tester, '画一张图');
      await pumpUntil(
        tester,
        () => demo.workspace.pendingAgentApproval != null,
        reason: () =>
            'phase=${demo.workspace.turns.lastOrNull?.phase} failure=${demo.workspace.turns.lastOrNull?.failure} requests=${requests.length} generations=${server.generations.length} events=${demo.workspace.turns.lastOrNull?.agentEvents.values.map((e) => e.result)}',
      );
      expect(find.byKey(const ValueKey('agent-approval')), findsOneWidget);
      expect(effects, 0);
      expect(tester.takeException(), isNull);
      if (action == 'approve') {
        final activity = find.byKey(const ValueKey('agent-tool-activity-heading'));
        await tester.ensureVisible(activity);
        await tester.tap(activity);
        await tester.pump();
        // Collapsing activity must never hide the separate approval controls.
        expect(find.byKey(const ValueKey('agent-approval')), findsOneWidget);
        await tester.tap(activity);
        await tester.pump();
      }
      switch (action) {
        case 'approve':
          final approve = find.byKey(const ValueKey('agent-approve'));
          await tester.ensureVisible(approve);
          await tester.tap(approve);
          await pumpUntil(tester, () => !demo.workspace.sending);
          expect(effects, 1);
          expect(find.text('已完成'), findsOneWidget);
          expect(find.text('本地测试图片'), findsOneWidget);
        case 'reject':
          final reject = find.byKey(const ValueKey('agent-reject'));
          await tester.ensureVisible(reject);
          await tester.tap(reject);
          await pumpUntil(tester, () => !demo.workspace.sending);
          expect(effects, 0);
          expect(find.text('未完成 · 查看原因'), findsOneWidget);
        case 'stop':
          await tester.tap(find.byKey(const ValueKey('genai-send')));
          await pumpUntil(tester, () => !demo.workspace.sending);
          expect(effects, 0);
          expect(demo.workspace.turns.single.phase, GenAiChatPhase.cancelled);
          await send(tester, '继续');
          await pumpUntil(tester, () => !demo.workspace.sending);
          expect(
            requests.last.history.any(
              (message) => decodeGenAiAgentRecord(message.content)?.result != null,
            ),
            isTrue,
          );
          expect(
            requests.last.history.any((message) => message.content == '画一张图'),
            isTrue,
          );
        case 'account':
          await demo.sessions.setOwner(null);
          await tester.pumpAndSettle();
          expect(effects, 0);
          expect(demo.workspace.turns, isEmpty);
          expect(find.text('画一张图'), findsNothing);
        case 'binding':
          scope.value = false;
          await tester.pumpAndSettle();
          expect(effects, 0);
          expect(demo.workspace.turns, isEmpty);
          expect(find.text('画一张图'), findsNothing);
        case 'timeout':
          await tester.pump(const Duration(milliseconds: 300));
          await pumpUntil(tester, () => !demo.workspace.sending);
          expect(effects, 0);
          expect(
            demo.workspace.turns.single.failure?.kind,
            GenAiFailureKind.timeout,
          );
        case 'dispose':
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(effects, 0);
          expect(demo.workspace.sending, isFalse);
      }
      expect(find.byKey(const ValueKey('agent-approval')), findsNothing);
      expect(demo.workspace.pendingAgentApproval, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('agent toggle shares the main conversation beside thinking', (tester) async {
    final server = JournalServer();
    final demo = await JournalClient.create(server);
    server.onGenerate =
        (body) => demo.workspace.agentEnabled ? server.finalAnswer(body, '已保留前面的上下文。') : 'Answer.';
    addTearDown(demo.dispose);
    final requests = <GenAiChatRequest>[];
    demo.workspace.configureAgent(
      runner: GenAiAgentRunner(
        tools: GenAiAgentToolRegistry([]),
        streamChat: (request, cancellation) {
          requests.add(request);
          return demo.repository.streamChat(request, cancellation);
        },
      ),
    );
    await show(tester, demo.workspace);
    final agent = find.byKey(const ValueKey('genai-agent-toggle'));
    final thinking = find.byKey(const ValueKey('genai-thinking-toggle'));
    expect(tester.getCenter(agent).dy, tester.getCenter(thinking).dy);
    expect(
      tester.getCenter(agent).dx,
      greaterThan(tester.getCenter(thinking).dx),
    );
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);
    final groupId = demo.workspace.groupId;
    await send(tester, 'My favorite color is blue');
    await pumpUntil(tester, () => !demo.workspace.sending);
    // The compact, noninteractive context indicator leaves room for this toggle.
    await tester.tap(agent);
    await tester.pump();
    await send(tester, 'Remember my color');
    await pumpUntil(tester, () => !demo.workspace.sending);
    expect(
      requests.single.history.any((message) => message.content == 'My favorite color is blue'),
      isTrue,
    );
    expect(demo.workspace.turns.last.isAgent, isTrue);
    await tester.tap(agent);
    await tester.pump();
    await send(tester, 'Continue our conversation');
    await pumpUntil(tester, () => !demo.workspace.sending);
    expect(demo.workspace.groupId, groupId);
    expect(
      demo.workspace.turns.map((turn) => turn.isAgent),
      [false, true, false],
    );
    expect(demo.workspace.turns.last.answer, 'Answer.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _Picker implements GenAiPicker {
  @override
  bool get supportsAudio => false;
  @override
  bool get supportsDocuments => true;
  @override
  Future<GenAiPickedFile?> pickAudio() async => null;
  @override
  Future<GenAiPickedFile?> pickDocument() async => null;
  @override
  Future<GenAiPickedFile?> pickImage() async => null;
}
