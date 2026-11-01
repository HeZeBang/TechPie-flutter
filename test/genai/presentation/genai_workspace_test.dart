import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:techpie/features/genai/presentation/audio/genai_audio_recorder.dart';
import 'package:techpie/features/genai/presentation/genai_history_sidebar.dart';
import 'package:techpie/features/genai/presentation/genai_icons.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';

import '../support/fakes.dart';
import '../support/journal_server.dart';
import '../support/workspace_server.dart';

/// Delegates to the in-memory server but can fail the model catalog and the
/// next chat request once, so the workspace's recovery actions can be driven.
final class _InterceptingTransport implements GenAiTransport {
  _InterceptingTransport(this.inner);

  final FakeGenAiServer inner;
  bool failCatalog = false;
  bool failNextChat = false;
  bool failNextChatNetwork = false;
  int catalogRequests = 0;

  @override
  Future<GenAiResponse> send({
    required String method,
    required Uri uri,
    required GenAiCancellation cancellation,
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
  }) {
    if (uri.path == '/htk/ai/aiModel/list') {
      catalogRequests++;
      if (failCatalog) {
        return Future.value(
          GenAiResponse(
            statusCode: 404,
            headers: const {'Content-Type': 'text/html; charset=utf-8'},
            bytes: Stream.value(
              utf8.encode(
                '<html><body><p>该服务暂不开放外网访问，仅支持校内访问</p></body></html>',
              ),
            ),
            close: () {},
          ),
        );
      }
    }
    if (method == 'POST' && uri.path == '/htk/chat/start/chat' && failNextChatNetwork) {
      failNextChatNetwork = false;
      return Future.value(
        GenAiResponse(
          statusCode: 404,
          headers: const {'Content-Type': 'text/html; charset=utf-8'},
          bytes: Stream.value(
            utf8.encode(
              '<html><body><p>该服务暂不开放外网访问，仅支持校内访问</p></body></html>',
            ),
          ),
          close: () {},
        ),
      );
    }
    if (method == 'POST' && uri.path == '/htk/chat/start/chat' && failNextChat) {
      failNextChat = false;
      return Future.value(
        GenAiResponse(
          statusCode: 500,
          headers: const {'Content-Type': 'application/json'},
          bytes: Stream.value(utf8.encode('{"success":false,"code":500}')),
          close: () {},
        ),
      );
    }
    return inner.send(
      method: method,
      uri: uri,
      cancellation: cancellation,
      headers: headers,
      body: body,
      bodyBytes: bodyBytes,
    );
  }

  @override
  void dispose() => inner.dispose();
}

final class _WorkspaceHarness {
  _WorkspaceHarness(
    this.backend,
    this.transport,
    this.sessions,
    this.chat,
    this.workspace,
  );

  final FakeGenAiServer backend;
  final _InterceptingTransport transport;
  final GenAiSessionService sessions;
  final GenAiChatService chat;
  final GenAiWorkspaceController workspace;

  void dispose() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
    transport.dispose();
  }
}

Future<_WorkspaceHarness> _wireWorkspace({bool failCatalog = false}) async {
  final backend = FakeGenAiServer(chunkDelay: Duration.zero);
  final transport = _InterceptingTransport(backend)..failCatalog = failCatalog;
  final api = GenAiApiClient(
    transport: transport,
    signer: const GenAiRequestSigner('synthetic-signing-salt'),
  );
  final sessions = GenAiSessionService(api: api, store: TestGenAiSessionStore());
  await sessions.setOwner(
    const GenAiOwner(
      primaryUserId: 'test-primary',
      studentId: FakeGenAiServer.studentId,
      bindingId: 'test-binding',
    ),
  );
  await sessions.connect(const GenAiCredential(token: FakeGenAiServer.token));
  final repository = GenAiRepository(api: api, sessions: sessions);
  final chat = GenAiChatService(repository);
  final workspace = GenAiWorkspaceController(
    sessions: sessions,
    repository: repository,
    chat: chat,
  );
  return _WorkspaceHarness(backend, transport, sessions, chat, workspace);
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  GenAiWorkspaceController workspace,
) async {
  await tester.pumpWidget(
    MaterialApp(home: GenAiWorkspace(controller: workspace, login: (_) async => null)),
  );
  await tester.pumpAndSettle();
}

void main() {
  Finder genAiIcon(GenAiGlyph glyph) => find.byWidgetPredicate(
        (widget) => widget is GenAiIcon && widget.glyph == glyph,
      );

  testWidgets('reopening variable-height history starts at the latest message', (tester) async {
    final server = JournalServer();
    server.rows['long'] = List.generate(
      18,
      (i) => {
        'id': 'row-$i',
        'question': i == 17
            ? 'Final saved question'
            : List.filled(100 + i * 13, 'Archive line $i').join('\n'),
        'answer': i == 17 ? 'Latest saved reply' : 'Archived reply $i',
        'aiType': 'Kimi-k3',
      },
    );
    final client = await JournalClient.create(server);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiWorkspace(
          controller: client.workspace,
          login: (_) async => const GenAiCredential(token: FakeGenAiServer.token),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final opening = client.workspace.openConversation('long', GenAiCancellation());
    await tester.pumpAndSettle();
    await opening;
    await tester.pumpAndSettle();
    expect(find.text('Latest saved reply'), findsOneWidget);
    expect(
      tester
          .getRect(find.text('Latest saved reply'))
          .overlaps(tester.getRect(find.byKey(const ValueKey('genai-thread')))),
      true,
    );
    expect(tester.takeException(), isNull);
  });

  Future<TestGenAiWorkspace> show(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    bool connected = true,
    double scale = 1,
    double keyboard = 0,
    Duration delay = const Duration(milliseconds: 1),
    GenAiAudioRecorder? audioRecorder,
    GenAiPicker? picker,
    GenAiLoginAction? login,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo = await TestGenAiWorkspace.create(connected: connected, chunkDelay: delay);
    addTearDown(demo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: AdaptiveFeedbackHost(
            key: adaptiveFeedbackHostKey,
            child: child!,
          ),
        ),
        home: GenAiWorkspace(
          controller: demo.workspace,
          audioRecorder: audioRecorder,
          picker: picker,
          login: login ?? (_) async => const GenAiCredential(token: FakeGenAiServer.token),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return demo;
  }

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('message actions confirm, cancel and recover on $size', (tester) async {
      final demo = await show(tester, size: size, delay: Duration.zero);
      for (final prompt in ['first', 'second']) {
        final sending = demo.workspace.send(prompt);
        await tester.pumpAndSettle();
        await sending;
      }
      final group = demo.workspace.groupId;
      final target = demo.workspace.turns.last.id;
      final menu = find.byKey(ValueKey('genai-turn-menu-$target'));
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除此轮及后续'));
      await tester.pumpAndSettle();
      expect(find.text('将永久删除 1 轮对话及其工具记录，所有设备同步生效。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(demo.workspace.turns, hasLength(2));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑并重新发送'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
        'edited',
      );
      await tester.tap(find.text('保存并重发'));
      await tester.pumpAndSettle();
      expect(demo.workspace.turns.map((t) => t.prompt), ['first', 'edited']);
      demo.workspace.newConversation();
      final opening = demo.workspace.openConversation(group, GenAiCancellation());
      await tester.pumpAndSettle();
      await opening;
      expect(demo.workspace.turns.map((t) => t.prompt), ['first', 'edited']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final checkSync in [true, false]) {
    testWidgets(
        'uncertain deletion recovers via ${checkSync ? 'sync button' : 'current history item'}',
        (tester) async {
      final demo = await show(
        tester,
        size: checkSync ? const Size(390, 844) : const Size(1280, 900),
        delay: Duration.zero,
      );
      for (final prompt in ['recovery retained', 'recovery removed']) {
        final sending = demo.workspace.send(prompt);
        await tester.pumpAndSettle();
        await sending;
      }
      final group = demo.workspace.groupId;
      demo.backend.loseDeleteResponse = true;
      final menu = find.byKey(ValueKey('genai-turn-menu-${demo.workspace.turns.last.id}'));
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除此轮及后续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(demo.workspace.archiveFailure, isNotNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(demo.workspace.turns, hasLength(2));
      await tester.enterText(find.byKey(const ValueKey('genai-prompt')), 'unsent draft');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('genai-send')));
      await tester.pumpAndSettle();
      expect(find.text('unsent draft'), findsOneWidget);
      expect(demo.workspace.turns, hasLength(2));
      if (checkSync) {
        await tester.tap(find.text('检查同步'));
      } else {
        await tester.tap(find.byTooltip('刷新历史'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('recovery retained').first);
      }
      await tester.pumpAndSettle();
      expect(demo.workspace.groupId, group);
      expect(demo.workspace.archiveFailure, isNull);
      expect(demo.workspace.turns.single.prompt, 'recovery retained');
      expect(find.text('检查同步'), findsNothing);
      expect(find.text('unsent draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed keyboard edit retains replacement and separate composer attachments',
      (tester) async {
    final demo = await show(tester, delay: Duration.zero);
    final sending = demo.workspace.send('original');
    await tester.pumpAndSettle();
    await sending;
    await demo.workspace.addImageAttachment('draft.png', [1, 2, 3]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('genai-prompt')), 'composer draft');
    demo.backend.loseDeleteResponse = true;
    await tester.tap(find.byKey(ValueKey('genai-turn-menu-${demo.workspace.turns.single.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑并重新发送'));
    await tester.pumpAndSettle();
    final editor = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
    await tester.enterText(editor, 'valuable replacement');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(demo.workspace.archiveFailure, isNotNull);
    expect(find.text('valuable replacement'), findsOneWidget);
    expect(find.text('composer draft'), findsOneWidget);
    expect(demo.workspace.attachments.single.name, 'draft.png');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('reopening saved vision chat builds network thumbnails and image viewer',
      (tester) async {
    final demo = await show(tester, delay: Duration.zero);
    await demo.workspace.addImageAttachment('red.png', [1, 2, 3]);
    await demo.workspace.addImageAttachment('blue.png', [4, 5, 6]);
    final sending = demo.workspace.send('Saved vision thumbnails');
    await tester.pumpAndSettle();
    await sending;
    final urls = demo.workspace.turns.single.attachedImageUrls;
    final id = demo.workspace.groupId;
    demo.workspace.newConversation();
    // Pump server recovery in the widget's fake-async zone.
    final opening = demo.workspace.openConversation(id, GenAiCancellation());
    await tester.pumpAndSettle();
    await opening;
    final thumbnails = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is NetworkImage &&
          urls.contains((widget.image as NetworkImage).url),
    );
    expect(thumbnails, findsNWidgets(urls.length));
    await tester.ensureVisible(thumbnails.first);
    await tester.pumpAndSettle();
    await tester.tap(thumbnails.first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(thumbnails, findsNWidgets(urls.length + 1));
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('typed chat sends only on submission and renders the reply', (tester) async {
    final demo = await show(tester);
    expect(find.text('GenAI'), findsOneWidget);
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

  testWidgets('login connects and logout clears the conversation', (tester) async {
    final demo = await show(tester, connected: false);
    expect(find.text('连接你的校园 AI'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('genai-connect')));
    await tester.pumpAndSettle();
    expect(demo.workspace.connected, isTrue);
    expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);
    await tester.tap(find.byTooltip('GenAI 账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('断开 GenAI 连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('断开'));
    await tester.pumpAndSettle();
    expect(find.text('连接你的校园 AI'), findsOneWidget);
    expect(demo.sessions.session, isNull);
  });

  testWidgets('campus-only catalog failure offers a working retry', (tester) async {
    final harness = await _wireWorkspace(failCatalog: true);
    addTearDown(harness.dispose);
    await _pumpWorkspace(tester, harness.workspace);
    expect(find.text('暂时无法连接校园 GenAI'), findsOneWidget);
    expect(find.text('请连接校园网或校园 VPN 后重试。'), findsOneWidget);
    expect(harness.workspace.catalogFailure?.kind, GenAiFailureKind.campusNetworkRequired);
    final attempts = harness.transport.catalogRequests;
    harness.transport.failCatalog = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(harness.transport.catalogRequests, greaterThan(attempts));
    expect(harness.workspace.catalogFailure, isNull);
    expect(find.text('暂时无法连接校园 GenAI'), findsNothing);
    expect(find.text('请连接校园网或校园 VPN 后重试。'), findsNothing);
    expect(find.text('Test chat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed last turn can be retried in place', (tester) async {
    final harness = await _wireWorkspace();
    addTearDown(harness.dispose);
    await _pumpWorkspace(tester, harness.workspace);
    harness.transport.failNextChat = true;
    await tester.enterText(find.byKey(const ValueKey('genai-prompt')), 'retry me');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();
    expect(harness.workspace.turns, hasLength(1));
    final failed = harness.workspace.turns.single;
    expect(failed.phase, GenAiChatPhase.failed);
    expect(failed.failure?.kind, GenAiFailureKind.rejected);
    final retry = find.byKey(const ValueKey('genai-retry-0'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(harness.workspace.turns, hasLength(1));
    expect(harness.workspace.turns.single.phase, GenAiChatPhase.completed);
    expect(harness.workspace.turns.single.answer, contains('Response to'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('last turn campus network failure shows the card and retries once', (tester) async {
    final harness = await _wireWorkspace();
    addTearDown(harness.dispose);
    await _pumpWorkspace(tester, harness.workspace);
    harness.transport.failNextChatNetwork = true;
    await tester.enterText(find.byKey(const ValueKey('genai-prompt')), 'campus retry');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();
    expect(harness.workspace.turns, hasLength(1));
    final failed = harness.workspace.turns.single;
    expect(failed.phase, GenAiChatPhase.failed);
    expect(failed.failure?.kind, GenAiFailureKind.campusNetworkRequired);
    // The last turn renders the campus card instead of a generic failure line.
    expect(find.text('暂时无法连接校园 GenAI'), findsOneWidget);
    expect(find.text('请连接校园网或校园 VPN 后重试。'), findsOneWidget);
    final retry = find.byKey(const ValueKey('genai-retry-0'));
    expect(retry, findsOneWidget);
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    // The failed turn is replaced, not appended.
    expect(harness.workspace.turns, hasLength(1));
    expect(harness.workspace.turns.single.phase, GenAiChatPhase.completed);
    expect(harness.workspace.turns.single.answer, contains('Response to'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed login can be retried from the connect panel', (tester) async {
    var attempts = 0;
    final demo = await show(
      tester,
      connected: false,
      delay: Duration.zero,
      login: (_) async {
        attempts++;
        if (attempts == 1) throw StateError('synthetic login failure');
        return const GenAiCredential(token: FakeGenAiServer.token);
      },
    );
    expect(find.text('连接你的校园 AI'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('genai-connect')));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(demo.workspace.connected, isFalse);
    expect(find.text('无法完成 GenAI 登录，请重试'), findsOneWidget);
    // The same control stays available for another attempt.
    await tester.tap(find.byKey(const ValueKey('genai-connect')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(demo.workspace.connected, isTrue);
    expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bound IDS without a school ID offers identity resolution', (tester) async {
    final demo = await TestGenAiWorkspace.create(connected: false);
    addTearDown(demo.dispose);
    await demo.sessions.setOwner(null);
    var connects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiWorkspace(
          controller: demo.workspace,
          campusBound: true,
          login: (_) async => throw StateError('manual login must not run'),
          onCampusLogin: () => connects++,
          onBindCampus: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('校园身份待同步'), findsOneWidget);
    expect(find.text('绑定校园账号'), findsNothing);
    expect(find.text('管理校园账号'), findsNothing);
    await tester.tap(find.text('使用现有 IDS 会话连接'));
    await tester.pump();
    expect(connects, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact drawer opens history, image creation and account usage', (tester) async {
    final demo = await show(tester, size: const Size(674, 1000), delay: Duration.zero);
    final sending = demo.workspace.send('drawer history entry');
    await tester.pumpAndSettle();
    await sending;
    demo.workspace.newConversation();
    await tester.pumpAndSettle();
    Future<void> openDrawer() async {
      await tester.tap(find.byTooltip('打开导航与历史'));
      await tester.pumpAndSettle();
    }

    await openDrawer();
    expect(find.byTooltip('搜索对话'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索对话'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '搜索历史对话'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(InkWell, 'drawer history entry'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(demo.workspace.turns.single.prompt, 'drawer history entry');

    await openDrawer();
    await tester.tap(find.text('图片创作'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-image-prompt')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('返回对话'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);

    await openDrawer();
    await tester.tap(find.byTooltip('GenAI 账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用量与额度'));
    await tester.pumpAndSettle();
    expect(find.text('免费额度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1200, 900), const Size(375, 812)]) {
    testWidgets('usage opens as a bounded modal over the live shell on $size', (tester) async {
      final demo = await show(tester, size: size, delay: Duration.zero);
      if (size.width < 960) {
        await tester.tap(find.byTooltip('打开导航与历史'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('GenAI 账户'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('用量与额度'));
      await tester.pumpAndSettle();
      final modal = find.byKey(const ValueKey('genai-usage-dialog'));
      expect(modal, findsOneWidget);
      final expectedWidth = size.width - 32 < 500 ? size.width - 32 : 500.0;
      expect(tester.getSize(modal).width, expectedWidth);
      expect(tester.getSize(modal).width, lessThanOrEqualTo(500));
      // The modal overlays the workspace: the shell composer and its single
      // Scaffold are still mounted, so this is not a pushed page.
      expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('免费额度'), findsOneWidget);
      expect(demo.workspace.turns, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('system back leaves inline images first and drawer exit leaves the page',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Scaffold(body: Text('TechPie host'))),
    );
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => GenAiWorkspace(controller: demo.workspace, login: (_) async => null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开导航与历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片创作'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-image-prompt')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);
    expect(find.text('TechPie host'), findsNothing);

    await tester.tap(find.byTooltip('打开导航与历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回 TechPie'));
    await tester.pumpAndSettle();
    expect(find.text('TechPie host'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new chat shortcut never interrupts a streaming reply', (tester) async {
    final demo = await show(tester, delay: const Duration(milliseconds: 20));
    await tester.enterText(find.byKey(const ValueKey('genai-prompt')), 'keep streaming');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(demo.workspace.sending, isTrue);
    final group = demo.workspace.groupId;
    for (final modifier in [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.controlLeft]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }
    expect(demo.workspace.groupId, group);
    expect(demo.workspace.turns, hasLength(1));
    await tester.pumpAndSettle();
    expect(demo.workspace.turns.single.answer, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape preserves draft and stopped turn retry expires after a new turn',
      (tester) async {
    final demo = await show(tester, delay: const Duration(milliseconds: 20));
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      List.filled(50, 'test stop').join(' '),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    for (var step = 0; step < 50 && demo.workspace.turns.single.answer.isEmpty; step++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(demo.workspace.sending, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      'Keep this next question',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('genai-prompt'))).controller!.text,
      'Keep this next question',
    );
    expect(demo.workspace.contextUsage, isNull);
    expect(demo.workspace.turns.single.phase, GenAiChatPhase.cancelled);
    expect(demo.workspace.turns.single.answer, isNotEmpty);
    expect(find.byKey(const ValueKey('genai-retry-0')), findsOneWidget);

    final sending = demo.workspace.send('Continue with another question');
    // Network delay timers can outlive a settled frame after layout changes.
    for (var step = 0; step < 500 && demo.workspace.sending; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(demo.workspace.sending, isFalse);
    await sending;
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('genai-thread')),
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    expect(demo.workspace.turns, hasLength(2));
    expect(demo.workspace.turns.first.phase, GenAiChatPhase.cancelled);
    expect(demo.workspace.turns.last.phase, GenAiChatPhase.completed);
    expect(find.byKey(const ValueKey('genai-copy-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-retry-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('streaming respects reading position until return to latest', (tester) async {
    final demo = await show(tester, delay: const Duration(milliseconds: 10));
    final first = demo.workspace.send(List.generate(40, (i) => 'Paragraph $i.\n').join('\n'));
    for (var step = 0; step < 500 && demo.workspace.sending; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(demo.workspace.sending, isFalse);
    await first;
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byKey(const ValueKey('genai-thread')));
    final scroll = list.controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(200));

    final next = demo.workspace.send('Another Markdown example');
    await tester.pump(const Duration(milliseconds: 80));
    scroll.jumpTo(200);
    for (var step = 0; step < 500 && demo.workspace.sending; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(demo.workspace.sending, isFalse);
    await next;
    await tester.pumpAndSettle();
    expect(scroll.offset, 200);
    expect(find.byKey(const ValueKey('genai-scroll-latest')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('genai-scroll-latest')));
    await tester.pumpAndSettle();
    expect(scroll.position.extentBefore, lessThan(1));
    expect(find.byKey(const ValueKey('genai-scroll-latest')), findsNothing);
    expect(find.byKey(const ValueKey('genai-context-status')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new conversation and account switch remove drafts and previous output',
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

  testWidgets('IME composition and Shift Enter do not submit a message', (tester) async {
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

  testWidgets('native workspace hides unavailable audio and file actions', (tester) async {
    await show(tester);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '测试语音播报',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();

    final ttsButton = find.byKey(const ValueKey('genai-tts-0'));
    expect(ttsButton, findsNothing);
    expect(find.byKey(const ValueKey('genai-audio-stt')), findsNothing);
    expect(find.byKey(const ValueKey('genai-upload-file')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('microphone recording shows timer and waveform and can be cancelled', (tester) async {
    final recorder = FakeGenAiAudioRecorder();
    await show(tester, audioRecorder: recorder);

    final micButton = find.byKey(const ValueKey('genai-audio-stt'));
    expect(micButton, findsOneWidget);

    await tester.tap(micButton);
    await tester.pump();
    expect(recorder.startCalls, 1);
    expect(recorder.isRecording, isTrue);

    expect(
      find.byKey(const ValueKey('genai-recording-duration')),
      findsOneWidget,
    );
    expect(find.text('正在录音 00:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('正在录音 00:02'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('genai-cancel-recording')));
    await tester.pumpAndSettle();

    expect(recorder.cancelCalls, 1);
    expect(recorder.isRecording, isFalse);
    expect(
      find.byKey(const ValueKey('genai-recording-duration')),
      findsNothing,
    );
  });

  testWidgets('finishing microphone recording stops recorder and transcribes audio to draft',
      (tester) async {
    final recorder = FakeGenAiAudioRecorder(
      recordedBytes: Uint8List.fromList([1, 2, 3, 4]),
    );
    await show(tester, audioRecorder: recorder);

    await tester.tap(find.byKey(const ValueKey('genai-audio-stt')));
    await tester.pump();
    expect(recorder.isRecording, isTrue);

    await tester.tap(find.byKey(const ValueKey('genai-finish-recording')));
    await tester.pumpAndSettle();

    expect(recorder.stopCalls, 1);
    expect(recorder.isRecording, isFalse);
    expect(
      find.byKey(const ValueKey('genai-recording-duration')),
      findsNothing,
    );

    final promptFinder = find.byKey(const ValueKey('genai-prompt'));
    final textField = tester.widget<TextField>(promptFinder);
    expect(textField.controller!.text, '你好，这是通过语音识别转换的文字内容。');
  });

  testWidgets('microphone recording handles permission denial gracefully', (tester) async {
    final recorder = FakeGenAiAudioRecorder(permission: false);
    await show(tester, audioRecorder: recorder);

    await tester.tap(find.byKey(const ValueKey('genai-audio-stt')));
    await tester.pumpAndSettle();

    expect(recorder.startCalls, 0);
    expect(find.text('无法访问麦克风，请检查权限设置'), findsOneWidget);
  });

  testWidgets('uploading image adds attachment chip without refreshing or resetting conversation',
      (tester) async {
    final picker = FakeGenAiPicker(
      nextImage: GenAiPickedFile(
        name: 'sample_photo.png',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
      ),
    );
    final demo = await show(tester, picker: picker);

    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '分析这幅图片',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
    await tester.pumpAndSettle();
    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    expect(imageBtn, findsOneWidget);

    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(picker.pickImageCalls, 1);
    expect(demo.workspace.connected, isTrue);
    expect(demo.workspace.attachments.length, 1);
    expect(demo.workspace.attachments.first.name, 'sample_photo.png');
    expect(find.text('sample_photo.png'), findsOneWidget);

    expect(find.text('分析这幅图片'), findsOneWidget);

    // Removing the attachment chip works and retains connected state
    await tester.tap(genAiIcon(GenAiGlyph.close));
    await tester.pumpAndSettle();
    expect(demo.workspace.attachments, isEmpty);
    expect(demo.workspace.connected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'uploading image and pressing send displays image in user bubble and preserves image bytes',
      (tester) async {
    final sampleBytes = Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      6,
      0,
      0,
      0,
      31,
      21,
      196,
      137,
      0,
      0,
      0,
      11,
      73,
      68,
      65,
      84,
      120,
      156,
      99,
      96,
      0,
      0,
      0,
      2,
      0,
      1,
      226,
      33,
      188,
      51,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ]);
    final picker = FakeGenAiPicker(
      nextImage: GenAiPickedFile(
        name: 'sample_photo.png',
        bytes: sampleBytes,
      ),
    );
    final demo = await show(tester, picker: picker);

    await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
    await tester.pumpAndSettle();
    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments.length, 1);
    expect(demo.workspace.hasPendingUploads, isFalse);

    final sendBtn = find.byKey(const ValueKey('genai-send'));
    await tester.tap(sendBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments, isEmpty);
    expect(demo.workspace.turns.length, 1);
    final turn = demo.workspace.turns.first;
    expect(turn.prompt, '请分析这张图片');
    expect(turn.attachedImageBytes, equals(sampleBytes));
    expect(turn.attachedImageUrl, isNotNull);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('genai-thread')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed upload blocks send, shows failure badge and warning, and allows retry',
      (tester) async {
    final sampleBytes = Uint8List.fromList([1, 2, 3, 4]);
    final picker = FakeGenAiPicker(
      nextImage: GenAiPickedFile(
        name: 'failed_image.png',
        bytes: sampleBytes,
      ),
    );
    final demo = await show(tester, picker: picker);

    demo.backend.failUpload = true;

    await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
    await tester.pumpAndSettle();
    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments.length, 1);
    expect(demo.workspace.hasFailedUploads, isTrue);

    expect(find.textContaining('上传失败'), findsOneWidget);

    final sendBtn = find.byKey(const ValueKey('genai-send'));
    expect(tester.widget<IconButton>(sendBtn).onPressed, isNull);

    final retryBtn = find.byKey(
      ValueKey(
        'genai-retry-attachment-${demo.workspace.attachments.first.id}',
      ),
    );
    expect(retryBtn, findsOneWidget);

    demo.backend.failUpload = false;

    await tester.tap(retryBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.hasFailedUploads, isFalse);
    expect(
      demo.workspace.attachments.first.imageUrl,
      contains('temp/test-upload-'),
    );
    expect(find.textContaining('上传失败'), findsNothing);
    expect(tester.widget<IconButton>(sendBtn).onPressed, isNotNull);

    await tester.tap(sendBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments, isEmpty);
    expect(demo.workspace.turns.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uploading image displays thumbnail in composer and tapping opens image dialog',
      (tester) async {
    final sampleBytes = Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      6,
      0,
      0,
      0,
      31,
      21,
      196,
      137,
      0,
      0,
      0,
      11,
      73,
      68,
      65,
      84,
      120,
      156,
      99,
      96,
      0,
      0,
      0,
      2,
      0,
      1,
      226,
      33,
      188,
      51,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ]);
    final picker = FakeGenAiPicker(
      nextImage: GenAiPickedFile(
        name: 'thumbnail_test.png',
        bytes: sampleBytes,
      ),
    );
    final demo = await show(tester, picker: picker);

    await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
    await tester.pumpAndSettle();
    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments.length, 1);
    final attId = demo.workspace.attachments.first.id;

    final thumbFinder = find.byKey(ValueKey('genai-attachment-thumbnail-$attId'));
    expect(thumbFinder, findsOneWidget);

    await tester.tap(thumbFinder);
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: genAiIcon(GenAiGlyph.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar session search filters in real time with debounce', (tester) async {
    final demo = await show(
      tester,
      size: const Size(1200, 900),
      delay: Duration.zero,
    );
    await demo.workspace.reloadModels();
    await tester.pumpAndSettle();

    // Send first conversation
    final send1 = demo.workspace.send('alpha physics research');
    for (var i = 0; i < 300 && demo.workspace.sending; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await send1;
    await tester.pumpAndSettle();

    // Start new conversation and send second
    demo.workspace.newConversation();
    final send2 = demo.workspace.send('beta chemistry notes');
    for (var i = 0; i < 300 && demo.workspace.sending; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await send2;
    await tester.pumpAndSettle();

    // Refresh history in sidebar
    await tester.tap(find.byTooltip('刷新历史'));
    await tester.pumpAndSettle();

    // The open conversation's title also appears in the header; count rows.
    Finder historyItem(String text) => find.descendant(
          of: find.byType(GenAiHistorySidebar),
          matching: find.byWidgetPredicate((w) => w is Text && w.data == text),
        );

    expect(historyItem('alpha physics research'), findsOneWidget);
    expect(historyItem('beta chemistry notes'), findsOneWidget);

    await tester.tap(find.byTooltip('搜索对话'));
    await tester.pumpAndSettle();
    final sidebarSearch = find.widgetWithText(TextField, '搜索历史对话');
    expect(sidebarSearch, findsOneWidget);
    final searchField = tester.widget<TextField>(
      find.byKey(const ValueKey('genai-search-input')),
    );
    expect(searchField.decoration!.hintText, '搜索历史对话');
    expect(searchField.decoration!.prefixIcon, isNull);
    final searchBorder = searchField.decoration!.border! as OutlineInputBorder;
    expect(searchBorder.borderRadius, BorderRadius.circular(9));
    expect(searchBorder.borderSide.width, 1);
    expect(searchField.textAlignVertical, TextAlignVertical.center);
    expect(searchField.strutStyle!.height, 1.5);
    expect(searchField.strutStyle!.forceStrutHeight, isTrue);
    expect(searchField.decoration!.contentPadding, const EdgeInsets.all(12));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('genai-search-input')),
        matching: find.byType(GenAiIcon),
      ),
      findsNothing,
    );

    // Search results and the shared sidebar model filter together.
    // Type 'alpha' in the search dialog
    await tester.enterText(sidebarSearch, 'alpha');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(historyItem('alpha physics research'), findsOneWidget);
    expect(historyItem('beta chemistry notes'), findsNothing);
    final dialogResult = find.byType(Dialog);
    expect(
      find.descendant(
        of: dialogResult,
        matching: find.widgetWithText(InkWell, 'alpha physics research'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialogResult,
        matching: find.widgetWithText(InkWell, 'beta chemistry notes'),
      ),
      findsNothing,
    );
    // The row is a title line plus the available time styled as the draft
    // preview, and never a ListTile. The API exposes no independent content
    // preview without fetching each conversation.
    expect(
      find.descendant(of: dialogResult, matching: find.byType(ListTile)),
      findsNothing,
    );
    final resultTitle = find.descendant(
      of: dialogResult,
      matching: find.text('alpha physics research'),
    );
    expect(resultTitle, findsOneWidget);
    expect(tester.widget<Text>(resultTitle).maxLines, 1);
    final resultRow = find.descendant(
      of: dialogResult,
      matching: find.widgetWithText(InkWell, 'alpha physics research'),
    );
    final resultLines = tester
        .widgetList<Text>(find.descendant(of: resultRow, matching: find.byType(Text)))
        .toList();
    expect(resultLines, hasLength(2));
    expect(resultLines.first.data, 'alpha physics research');
    expect(resultLines.first.maxLines, 1);
    // The second line is the draft preview treatment: 12 px muted text.
    expect(resultLines.last.style?.fontSize, 12);
    expect(resultLines.last.style?.color, isNotNull);

    // Clear search
    await tester.enterText(sidebarSearch, '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(historyItem('alpha physics research'), findsOneWidget);
    expect(historyItem('beta chemistry notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
