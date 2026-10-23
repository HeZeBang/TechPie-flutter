import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';
import 'package:techpie/features/genai/presentation/genai_tools_page.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';

import '../support/fakes.dart';

void main() {
  late DemoGenAiBackend backend;
  late ScriptedTransport transport;
  late GenAiSessionService sessions;
  late GenAiChatService chat;
  late GenAiWorkspaceController workspace;
  late List<(String, Completer<GenAiResponse>)> requests;

  GenAiResponse history(String title, {int total = 1}) => response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              {'chatGroupId': title, 'question': title},
            ],
            'total': total,
          },
        },
      );

  Future<void> initialize() async {
    requests = [];
    backend = DemoGenAiBackend(chunkDelay: Duration.zero);
    transport = ScriptedTransport((request) {
      if (request.uri.path.endsWith('/listByContentGroup')) {
        final gate = Completer<GenAiResponse>();
        requests.add((request.uri.queryParameters['question'] ?? '', gate));
        return gate.future;
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
    final api = GenAiApiClient(
      transport: transport,
      signer: const GenAiRequestSigner('synthetic'),
    );
    sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    await sessions.setOwner(ownerA);
    await sessions
        .connect(const GenAiCredential(token: DemoGenAiBackend.token));
    final repository = GenAiRepository(api: api, sessions: sessions);
    chat = GenAiChatService(repository);
    workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: repository,
      chat: chat,
    );
    await workspace.reloadModels();
  }

  tearDown(() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
    backend.dispose();
  });

  Future<void> show(WidgetTester tester, {bool tools = false}) async {
    await initialize();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: tools
            ? GenAiToolsPage(workspace: workspace, demo: true)
            : GenAiWorkspace(
                controller: workspace,
                demo: true,
                login: (_) async => null,
              ),
      ),
    );
    await tester.pump();
  }

  for (final tools in [false, true]) {
    testWidgets(
        '${tools ? 'tools' : 'sidebar'} newest search replaces an in-flight search and stays busy',
        (tester) async {
      await show(tester, tools: tools);
      expect(requests, hasLength(1));
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (tools
                ? widget.decoration?.labelText == '搜索对话'
                : widget.decoration?.hintText == '搜索历史对话'),
      );
      await tester.enterText(search, 'latest');
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(requests.map((r) => r.$1), ['', 'latest']);
      requests.first.$2.complete(history('stale result'));
      await tester.pump();
      expect(find.text('stale result'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      if (tools) {
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == '刷新',
                ),
              )
              .onPressed,
          isNull,
        );
      }
      requests.last.$2
          .complete(history('latest result', total: tools ? 40 : 1));
      await tester.pumpAndSettle();
      expect(find.text('latest result'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      if (tools) {
        final more = find.widgetWithText(OutlinedButton, '加载更多');
        final oldMore = tester.widget<OutlinedButton>(more).onPressed!;
        await tester.enterText(search, 'replacement');
        await tester.pump();
        expect(tester.widget<OutlinedButton>(more).onPressed, isNull);
        // A callback already queued before the debounce must also force page 1.
        oldMore();
        await tester.pump();
        expect(
          transport.requests.last.uri.queryParameters['question'],
          'replacement',
        );
        expect(transport.requests.last.uri.queryParameters['pageNo'], '1');
        requests.last.$2.complete(history('replacement result'));
        await tester.pumpAndSettle();
        expect(find.text('latest result'), findsNothing);
        expect(find.text('replacement result'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('history failure is visible and only retries on user request',
      (tester) async {
    await show(tester);
    requests.single.$2
        .completeError(const GenAiFailure(GenAiFailureKind.transport));
    await tester.pumpAndSettle();
    expect(find.text('重试加载历史'), findsOneWidget);
    expect(find.text('暂无历史对话'), findsNothing);
    workspace.setThinking(true);
    workspace.setThinking(false);
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    await tester.tap(find.text('重试加载历史'));
    await tester.pump();
    expect(requests, hasLength(2));
    requests.last.$2.complete(history('recovered'));
    await tester.pumpAndSettle();
    expect(find.text('recovered'), findsOneWidget);
    expect(find.text('重试加载历史'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('delete confirmation cannot authorize a different account',
      (tester) async {
    await show(tester);
    requests.single.$2.complete(history('old account chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('对话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除对话'));
    await tester.pumpAndSettle();
    final oldConfirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '删除'))
        .onPressed!;
    await sessions.setOwner(
      const GenAiOwner(
        primaryUserId: 'new-primary',
        studentId: DemoGenAiBackend.studentId,
        bindingId: 'new-binding',
      ),
    );
    await sessions
        .connect(const GenAiCredential(token: DemoGenAiBackend.token));
    await tester.pump();
    oldConfirm();
    await tester.pump();
    expect(
      transport.requests.where((r) => r.uri.path.endsWith('/delete/groupId')),
      isEmpty,
    );
    expect(find.text('账号已切换'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '删除'))
          .onPressed,
      isNull,
    );
    requests.last.$2.complete(history('new account chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('new account chat'), findsOneWidget);
    expect(find.text('old account chat'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('old account menu cannot disconnect a replacement session',
      (tester) async {
    await show(tester);
    requests.single.$2.complete(history('initial chat'));
    await tester.pumpAndSettle();
    final menu = find.byWidgetPredicate(
      (widget) =>
          widget is PopupMenuButton<String> && widget.tooltip == 'GenAI 账户',
    );
    final oldAction = tester.widget<PopupMenuButton<String>>(menu).onSelected!;
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await sessions.setOwner(
      const GenAiOwner(
        primaryUserId: 'replacement-primary',
        studentId: DemoGenAiBackend.studentId,
        bindingId: 'replacement-binding',
      ),
    );
    await sessions
        .connect(const GenAiCredential(token: DemoGenAiBackend.token));
    await tester.pump();
    oldAction('disconnect');
    await tester.pump();
    expect(sessions.session, isNotNull);
    expect(sessions.owner?.primaryUserId, 'replacement-primary');
    requests.last.$2.complete(history('replacement chat'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
