import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/presentation/genai_tools_page.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

void main() {
  late FakeGenAiServer backend;
  late GenAiSessionService sessions;
  late GenAiWorkspaceController workspace;
  late GenAiChatService chat;
  Completer<void>? generationGate;
  Completer<void>? historyGate;
  var historyFails = false;

  setUp(() async {
    generationGate = null;
    historyGate = null;
    historyFails = false;
    backend = FakeGenAiServer(chunkDelay: Duration.zero);
    final transport = ScriptedTransport((request) async {
      if (request.uri.path == '/htk/chat/start/chat') await generationGate?.future;
      if (request.uri.path == '/htk/ai-image-history/list') {
        await historyGate?.future;
        if (historyFails) throw const GenAiFailure(GenAiFailureKind.transport);
      }
      return backend.send(
        method: request.method,
        uri: request.uri,
        cancellation: request.cancellation,
        headers: request.headers,
        body: request.body,
        bodyBytes: request.bodyBytes,
      );
    });
    final api = GenAiApiClient(transport: transport, signer: const GenAiRequestSigner('synthetic'));
    sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: FakeGenAiServer.token));
    final repository = GenAiRepository(api: api, sessions: sessions);
    chat = GenAiChatService(repository);
    workspace = GenAiWorkspaceController(sessions: sessions, repository: repository, chat: chat);
    await workspace.reloadModels();
  });
  tearDown(() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
    backend.dispose();
  });

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(
          workspace: workspace,
          initialTab: 1,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('generation survives page navigation, deduplicates and reuses the result',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('genai-image-prompt')), 'Campus at sunrise');
    generationGate = Completer<void>();
    await tester.pump();
    await tester.tap(find.text('生成 1 张图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始生成'));
    await tester.pumpAndSettle();
    expect(workspace.imageStudio.generating, isTrue);
    await tester.pumpWidget(const SizedBox());
    await show(tester);
    expect(find.text('Campus at sunrise'), findsOneWidget);
    expect(find.text('正在生成…'), findsOneWidget);
    generationGate!.complete();
    await tester.pumpAndSettle();
    expect(workspace.imageStudio.generating, isFalse);
    expect(workspace.imageStudio.pending, isEmpty);
    await tester.ensureVisible(find.text('图片历史'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    final tile = find.byKey(const ValueKey('genai-image-preview-image-1'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-image-preview')), findsOneWidget);
    await tester.ensureVisible(find.text('复用描述'));
    await tester.tap(find.text('复用描述'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('genai-image-prompt'))).controller!.text,
      'Campus at sunrise',
    );
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await sessions.setOwner(ownerB);
    await tester.pumpAndSettle();
    expect(find.text('账号已切换'), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-image-preview')), findsNothing);
    expect(find.text('保存图片'), findsNothing);
    expect(find.text('复用描述'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('account change clears the draft and rejects late image completion', () async {
    final studio = workspace.imageStudio;
    studio.draft.prompt = 'private draft';
    generationGate = Completer<void>();
    final generation = studio.generate(
      GenAiImageRequest(
        prompt: 'private image',
        model: workspace.imageModels.first,
        groupId: 'private-job',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await sessions.setOwner(ownerB);
    generationGate!.complete();
    await generation;
    expect(studio.draft.prompt, isEmpty);
    expect(studio.pending, isEmpty);
    expect(studio.generating, isFalse);
    expect(studio.failure, isNull);
  });

  testWidgets('history loading and retry do not block editing or show false empty state',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    historyGate = Completer<void>();
    historyFails = true;
    await show(tester);
    await tester.enterText(
      find.byKey(const ValueKey('genai-image-prompt')),
      'Draft during refresh',
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(const ValueKey('genai-image-generate'))).onPressed,
      isNotNull,
    );
    expect(find.text('没有图片记录'), findsNothing);
    historyGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('没有图片记录'), findsNothing);
    expect(find.text('重试加载'), findsOneWidget);
    historyFails = false;
    await tester.ensureVisible(find.text('重试加载'));
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(find.text('没有图片记录'), findsOneWidget);
    expect(find.text('重试加载'), findsNothing);
    expect(find.text('Draft during refresh'), findsOneWidget);
  });
}
