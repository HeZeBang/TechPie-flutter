import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';
import 'package:techpie/features/genai/presentation/genai_conversation_menu.dart';
import 'package:techpie/features/genai/presentation/genai_history_sidebar.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

void main() {
  late FakeGenAiServer backend;
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

  GenAiResponse historyOf(List<String> titles) => response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              for (final title in titles) {'chatGroupId': title, 'question': title},
            ],
            'total': titles.length,
          },
        },
      );

  Future<void> initialize() async {
    requests = [];
    backend = FakeGenAiServer(chunkDelay: Duration.zero);
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
    await sessions.connect(const GenAiCredential(token: FakeGenAiServer.token));
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

  Future<void> show(WidgetTester tester) async {
    await initialize();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiWorkspace(
          controller: workspace,
          login: (_) async => null,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sidebar newest search replaces an in-flight search and older pages', (tester) async {
    await show(tester);
    expect(requests, hasLength(1));
    await tester.tap(find.byTooltip('搜索对话'));
    await tester.pump();
    // The draft search dialog owns a keyed plain field.
    final search = find.byKey(const ValueKey('genai-search-input'));
    await tester.enterText(search, 'latest');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();
    expect(requests.map((r) => r.$1), ['', 'latest']);
    requests.first.$2.complete(history('stale result'));
    await tester.pump();
    expect(find.text('stale result'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    requests.last.$2.complete(history('latest result', total: 40));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('latest result')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final more =
        find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(TextButton, '加载更多'));
    final oldMore = tester.widget<TextButton>(more).onPressed!;
    await tester.enterText(search, 'replacement');
    await tester.pump();
    // A callback already queued before the debounce must also force page 1.
    oldMore();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();
    expect(transport.requests.last.uri.queryParameters['question'], 'replacement');
    expect(transport.requests.last.uri.queryParameters['pageNo'], '1');
    requests.last.$2.complete(history('replacement result'));
    await tester.pumpAndSettle();
    expect(find.text('latest result'), findsNothing);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('replacement result')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('send and retry completion each keep one uncancelled history refresh',
      (tester) async {
    await show(tester);
    requests.single.$2.complete(history('initial'));
    await tester.pumpAndSettle();
    final original = transport.handle;
    transport.handle = (request) async => request.method == 'POST'
        ? response(type: 'text/event-stream', text: sseChunk(text: 'partial answer'))
        : original(request);
    await tester.enterText(find.byKey(const ValueKey('genai-prompt')), 'A question');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));

    Future<void> expectRefresh(int count) async {
      for (var step = 0; step < 30 && workspace.sending; step++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump();
      expect(workspace.sending, isFalse);
      expect(requests, hasLength(count));
      expect(
        transport.requests
            .lastWhere((request) => request.uri.path.endsWith('/listByContentGroup'))
            .cancellation
            .isCancelled,
        isFalse,
      );
      requests.last.$2.complete(history('refresh $count'));
      await tester.pumpAndSettle();
    }

    await expectRefresh(2);
    await tester.tap(find.byKey(const ValueKey('genai-retry-0')));
    await expectRefresh(3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('history failure is visible and only retries on user request', (tester) async {
    await show(tester);
    requests.single.$2.completeError(const GenAiFailure(GenAiFailureKind.transport));
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

  testWidgets('delete confirmation cannot authorize a different account', (tester) async {
    await show(tester);
    requests.single.$2.complete(history('old account chat'));
    await tester.pumpAndSettle();
    final row =
        find.ancestor(of: find.text('old account chat'), matching: find.byType(InkWell)).first;
    final rowHover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await rowHover.addPointer(location: tester.getCenter(row));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('对话操作')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除对话'));
    await tester.pumpAndSettle();
    final oldConfirm =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '删除')).onPressed!;
    await sessions.setOwner(
      const GenAiOwner(
        primaryUserId: 'new-primary',
        studentId: FakeGenAiServer.studentId,
        bindingId: 'new-binding',
      ),
    );
    await sessions.connect(const GenAiCredential(token: FakeGenAiServer.token));
    await tester.pump();
    oldConfirm();
    await tester.pump();
    expect(
      transport.requests.where((r) => r.uri.path.endsWith('/delete/groupId')),
      isEmpty,
    );
    expect(find.text('账号已切换'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '删除')).onPressed,
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
  testWidgets('old account menu cannot disconnect a replacement session', (tester) async {
    await show(tester);
    requests.single.$2.complete(history('initial chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('GenAI 账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('断开 GenAI 连接'));
    await tester.pumpAndSettle();
    final oldAction =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '断开')).onPressed!;
    await sessions.setOwner(
      const GenAiOwner(
        primaryUserId: 'replacement-primary',
        studentId: FakeGenAiServer.studentId,
        bindingId: 'replacement-binding',
      ),
    );
    await sessions.connect(const GenAiCredential(token: FakeGenAiServer.token));
    await tester.pump();
    oldAction();
    await tester.pump();
    expect(sessions.session, isNotNull);
    expect(sessions.owner?.primaryUserId, 'replacement-primary');
    expect(find.text('账号已切换'), findsNWidgets(2));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '断开')).onPressed, isNull);
    requests.last.$2.complete(history('replacement chat'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('history rows keep a 2 px gap and hold their menu inside the row', (tester) async {
    await show(tester);
    requests.single.$2.complete(historyOf(['alpha conversation', 'beta conversation']));
    await tester.pumpAndSettle();
    // Select the first conversation so the menu's hover wash is checked over
    // both an active and an idle row plate.
    expect(await workspace.openConversation('alpha conversation', GenAiCancellation()), isTrue);
    await tester.pumpAndSettle();

    final sidebar = find.byType(GenAiHistorySidebar);
    final rows = find.descendant(
      of: sidebar,
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('genai-history-row-');
      }),
    );
    expect(rows, findsNWidgets(2));

    final first = tester.getRect(rows.at(0));
    final second = tester.getRect(rows.at(1));
    // Draft row: 40 px plate, 2 px gap to the next plate.
    expect(first.height, 40);
    expect(second.height, 40);
    expect(second.top - first.bottom, greaterThanOrEqualTo(2));
    // Only the first row is selected; the idle plate stays transparent.
    expect(tester.widget<Material>(rows.at(0)).color, isNot(Colors.transparent));
    expect(tester.widget<Material>(rows.at(1)).color, Colors.transparent);

    // Draft rail: rows are inset 14 px from the rail's content edges.
    final rail = tester.getRect(sidebar);
    expect(first.left - rail.left, 14);
    expect(rail.right - first.right, inInclusiveRange(14, 15));

    final menu = find.descendant(of: rows.at(0), matching: find.byType(GenAiConversationMenu));
    expect(menu, findsOneWidget);
    final menuRect = tester.getRect(menu);
    // The 28 px menu target is a square centered in the 40 px row, inset 6 px
    // from the row's clipped end instead of sitting flush against it.
    expect(menuRect.size, const Size(28, 28));
    expect(first.right - menuRect.right, 6);
    expect(menuRect.top - first.top, 6);
    expect(first.bottom - menuRect.bottom, 6);
    expect(menuRect.left, greaterThanOrEqualTo(first.left));
    // Both the selected plate and a hovered more button paint into the clipped
    // rounded row, never its neighbour or the rail padding.
    for (final element in rows.evaluate()) {
      final plate = element.widget as Material;
      expect(plate.borderRadius, BorderRadius.circular(8));
      expect(plate.clipBehavior, Clip.antiAlias);
    }
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: first.center);
    await tester.pumpAndSettle();
    await mouse.moveTo(menuRect.center);
    await tester.pumpAndSettle();
    // The revealed target keeps the draft's 6 px square and paints a wash that
    // is distinct from whichever row plate sits behind it.
    for (var index = 0; index < 2; index++) {
      final row = rows.at(index);
      final button = find.descendant(of: row, matching: find.byType(GenAiConversationMenu));
      final buttonTheme = IconButtonTheme.of(tester.element(button));
      final buttonShape =
          buttonTheme.style!.shape!.resolve({WidgetState.hovered})! as RoundedRectangleBorder;
      expect(buttonShape.borderRadius, BorderRadius.circular(6));
      final wash = buttonTheme.style!.overlayColor!.resolve({WidgetState.hovered})!;
      expect(wash, isNot(tester.widget<Material>(row).color));
      expect(wash.a, inInclusiveRange(.08, .2));
      // The wash itself, not just the row plate, is clipped to the inset
      // 28 px target: the button's InkWell carries the 6 px rounded border.
      final ink = find.descendant(of: button, matching: find.byType(InkWell));
      expect(ink, findsOneWidget);
      expect(tester.getRect(ink), tester.getRect(button));
      expect(
        (tester.widget<InkWell>(ink).customBorder! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(6),
      );
    }
    expect(first.contains(tester.getRect(menu).topLeft), isTrue);
    expect(first.contains(tester.getRect(menu).bottomRight - const Offset(.01, .01)), isTrue);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
