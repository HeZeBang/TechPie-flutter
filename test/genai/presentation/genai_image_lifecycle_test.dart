import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:techpie/features/genai/presentation/genai_image_actions.dart';
import 'package:techpie/features/genai/presentation/genai_tools_page.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';

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
        builder: (context, child) => AdaptiveFeedbackHost(
          key: adaptiveFeedbackHostKey,
          child: child!,
        ),
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
    // Serve every history image as the same 96 × 96 PNG so the description
    // dialog can report decoded dimensions instead of inventing metadata.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAIAAABt+uBvAAAApElEQVR4nO3QMQ0AMAzAsCEpf1ADMwZ7m8NSAEQ+d0afzvpBPECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQoM0eMcZiSiv2Au4AAAAASUVORK5CYII=',
    );
    debugNetworkImageHttpClientProvider = () => _ImageHttpClient(png);
    _imageRequests = 0;
    addTearDown(() {
      debugNetworkImageHttpClientProvider = null;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    await show(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('genai-image-prompt')), 'Campus at sunrise');
    generationGate = Completer<void>();
    await tester.pump();
    final generate = find.byKey(const ValueKey('genai-image-generate'));
    await tester.ensureVisible(generate);
    expect(find.descendant(of: generate, matching: find.text('生成图片')), findsOneWidget);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('生成 1 张图片'), findsOneWidget);
    expect(find.text('生成'), findsOneWidget);
    expect(find.text('开始生成'), findsNothing);
    await tester.tap(find.text('生成'));
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
    await tester.ensureVisible(find.text('我的创作'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    final tile = find.byKey(const ValueKey('genai-image-preview-image-1'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('genai-image-preview'));
    expect(preview, findsOneWidget);
    // The header names the record prompt; the footer owns the secondary actions.
    expect(
      find.descendant(of: preview, matching: find.text('Campus at sunrise')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.text('用作参考')),
      findsOneWidget,
    );
    expect(find.byTooltip('复制链接'), findsOneWidget);
    expect(find.byTooltip('分享图片'), findsOneWidget);
    final downloadAction = find.byTooltip('下载图片');
    expect(downloadAction, findsOneWidget);
    // The separate "open original" action is gone; the preview itself is the
    // only way to view the record.
    expect(find.byTooltip('打开原图'), findsNothing);
    // Exactly one more-actions menu owns the destructive and descriptive
    // actions; the image itself no longer grows a second overflow button.
    expect(find.byTooltip('更多图片操作'), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-preview-more')), findsOneWidget);
    String? copiedLink;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedLink = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final actions = tester.widget<GenAiImageActions>(
      find.descendant(of: preview, matching: find.byType(GenAiImageActions)),
    );
    // The preview supplies its own footer, so the reusable action widget must
    // not add a second visible menu button over the image.
    expect(actions.showMenuButton, isFalse);
    final originalUri = actions.link!;
    await tester.tap(find.byTooltip('复制链接'));
    await tester.pumpAndSettle();
    expect(copiedLink, originalUri.toString());
    expect(find.text('已复制链接'), findsOneWidget);

    await tester.tap(find.byTooltip('更多图片操作'));
    await tester.pumpAndSettle();
    expect(find.text('查看描述'), findsOneWidget);
    expect(find.text('复用描述'), findsOneWidget);
    expect(find.text('删除图片'), findsOneWidget);
    expect(find.text('删除图片记录'), findsNothing);
    await tester.tap(find.text('查看描述'));
    await tester.pumpAndSettle();
    final description = find.byKey(const ValueKey('genai-image-description'));
    expect(description, findsOneWidget);
    // The caption is the header title; require the full prompt exactly once
    // within the description body, independently of that derived title.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('genai-description-body')),
        matching: find.text('Campus at sunrise'),
      ),
      findsOneWidget,
    );
    // The decoded frame supplies the dimensions; a 96 × 96 PNG reports 96 × 96.
    for (var i = 0; i < 200 && find.text('96 × 96').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(_imageRequests, greaterThan(0));
    expect(
      find.descendant(of: description, matching: find.text('尺寸')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: description, matching: find.text('96 × 96')),
      findsOneWidget,
    );
    // The record carries no quality metadata, so the description must not
    // invent one.
    expect(
      find.descendant(of: description, matching: find.text('质量')),
      findsNothing,
    );
    expect(
      find.descendant(of: description, matching: find.text('复用描述')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: description, matching: find.text('返回图片')),
      findsOneWidget,
    );
    await tester.tap(find.text('返回图片'));
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);

    await tester.tap(find.byTooltip('更多图片操作'));
    await tester.pumpAndSettle();
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
    expect(preview, findsNothing);
    expect(downloadAction, findsNothing);
    expect(find.text('复用描述'), findsNothing);
    // Painting debug variables must be restored before the binding checks
    // invariants at the end of the test body.
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
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

/// Serves [bytes] for every image request so the history preview decodes a real
/// frame in widget tests.
final class _ImageHttpClient implements HttpClient {
  _ImageHttpClient(this.bytes);

  final List<int> bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    _imageRequests++;
    return _ImageRequest(bytes);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

var _imageRequests = 0;

final class _ImageRequest implements HttpClientRequest {
  _ImageRequest(this.bytes);

  final List<int> bytes;
  final _headers = _ImageHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.bytes);

  final List<int> bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _ImageHeaders();

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ImageHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
