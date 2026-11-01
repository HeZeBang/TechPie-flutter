import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/presentation/genai_image_gallery.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/genai_tools_page.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

/// The 96 × 96 PNG used by the lifecycle test, served to every network image.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAIAAABt+uBvAAAApElEQVR4nO3QMQ0AMAzAsCEpf1ADMwZ7m8NSAEQ+d0afzvpBPECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQoM0eMcZiSiv2Au4AAAAASUVORK5CYII=',
);

var _imageRequests = 0;

Future<TestGenAiWorkspace> _showStudio(
  WidgetTester tester, {
  Size size = const Size(1200, 1200),
  double? stageWidth,
  double? localWidth,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
  addTearDown(demo.dispose);
  await demo.workspace.reloadModels();
  Widget page = GenAiToolsPage(
    key: ObjectKey(demo.workspace),
    workspace: demo.workspace,
    initialTab: 1,
    stageWidth: stageWidth,
  );
  if (localWidth != null) {
    page = Center(
      child: SizedBox(width: localWidth, height: size.height, child: page),
    );
  }
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
  return demo;
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    final lists = find.byType(ListView);
    final scrollable = lists.evaluate().isNotEmpty
        ? find.descendant(of: lists, matching: find.byType(Scrollable)).first
        : find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
    await tester.scrollUntilVisible(target, 240, scrollable: scrollable);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _generate(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('genai-image-prompt')),
    'Studio geometry check',
  );
  await tester.pump();
  final generate = find.byKey(const ValueKey('genai-image-generate'));
  await _reveal(tester, generate);
  await tester.tap(generate);
  await tester.pumpAndSettle();
  expect(find.text('生成 1 张图片'), findsOneWidget);
  await tester.tap(find.text('生成'));
  await tester.pumpAndSettle();
}

Future<void> _openPreview(WidgetTester tester) async {
  await tester.ensureVisible(find.text('我的创作'));
  await tester.pumpAndSettle();
  final gallery = find.byType(GenAiImageGallery);
  expect(gallery, findsOneWidget);
  final tile = find.descendant(of: gallery, matching: find.byType(InkWell)).first;
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('genai-image-preview')), findsOneWidget);
}

void main() {
  setUp(() {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('preset request sizes come from ratio and resolution, without quota copy',
      (tester) async {
    final demo = await _showStudio(tester);

    await tester.tap(find.byKey(const ValueKey('genai-image-model')));
    await tester.pumpAndSettle();
    expect(find.textContaining('扣除额度'), findsNothing);
    expect(find.textContaining('免费'), findsNothing);
    expect(find.text('Test image'), findsWidgets);
    await tester.tap(find.text('Test image').last);
    await tester.pumpAndSettle();

    final generate = find.byKey(const ValueKey('genai-image-generate'));
    await tester.enterText(
      find.byKey(const ValueKey('genai-image-prompt')),
      'Preset request',
    );
    await tester.pump();

    await _reveal(tester, generate);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.textContaining('1024x1024'), findsOneWidget);
    expect(find.textContaining('额度'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // Ratio and resolution together name the preset request size.
    final landscape = find.byKey(const ValueKey('genai-orientation-landscape'));
    await tester.ensureVisible(landscape);
    await tester.tap(landscape);
    await tester.pumpAndSettle();
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.textContaining('1136x640'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final resolution = find.byKey(const ValueKey('genai-image-resolution'));
    await tester.ensureVisible(resolution);
    await tester.tap(resolution);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2K · 2048 × 1152').last);
    await tester.pumpAndSettle();
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.textContaining('2048x1152'), findsOneWidget);
    expect(find.textContaining('额度'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(demo.workspace.imageStudio.generating, isFalse);
  });

  testWidgets('compact parameter dialog follows the phone summary and dialog geometry',
      (tester) async {
    await _showStudio(tester, size: const Size(390, 1000));

    final parameters = find.byKey(const ValueKey('genai-image-parameters'));
    expect(parameters, findsOneWidget);
    final summary = tester.widget<Text>(
      find.descendant(of: parameters, matching: find.textContaining('方形')),
    );
    expect(summary.style?.fontSize, 12);
    expect(summary.style?.fontWeight, FontWeight.w600);
    expect(
      summary.style?.color,
      Theme.of(tester.element(parameters)).colorScheme.onSurfaceVariant,
    );
    final rich = find.descendant(
      of: find.byWidget(summary),
      matching: find.byType(RichText),
    );
    expect(tester.widget<RichText>(rich).text.style?.fontWeight, FontWeight.w600);

    await tester.tap(parameters);
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('genai-image-parameters-dialog'));
    expect(dialog, findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('genai-parameters-body')),
              matching: find.text('质量'),
            ),
          )
          .style
          ?.fontSize,
      12,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('genai-parameters-surface'))).width,
      390 - 24,
    );
    final shape = tester.widget<Dialog>(dialog).shape! as RoundedRectangleBorder;
    expect((shape.borderRadius as BorderRadius).topLeft, const Radius.circular(14));

    final header = tester.widget<Padding>(
      find.byKey(const ValueKey('genai-parameters-header')),
    );
    expect(header.padding, const EdgeInsets.fromLTRB(16, 15, 16, 15));
    expect(
      tester.getSize(find.byKey(const ValueKey('genai-parameters-header'))).height,
      66,
    );
    final body = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('genai-parameters-body')),
    );
    expect(body.padding, const EdgeInsets.all(18));

    for (final orientation in ['landscape', 'square', 'portrait']) {
      final option = find.byKey(ValueKey('genai-orientation-$orientation'));
      expect(tester.getSize(option).height, greaterThanOrEqualTo(44));
    }
    final selected = find.byKey(const ValueKey('genai-orientation-square'));
    final selectedMaterial = tester.widget<Material>(
      find.ancestor(of: selected, matching: find.byType(Material)).first,
    );
    expect(selectedMaterial.elevation, greaterThan(0));

    // Custom fields appear only for the custom resolution, using the larger
    // tap target inside the phone dialog.
    expect(find.byKey(const ValueKey('genai-image-width')), findsNothing);
    final resolution = find.byKey(const ValueKey('genai-image-resolution'));
    await tester.tap(resolution);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-image-width')), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-image-height')), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('genai-image-width'))).contextMenuBuilder,
      genAiTextSelectionContextMenu,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact parameter summary stays semibold without overflow at text scale 1.6',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _showStudio(tester, size: const Size(320, 900));

    final parameters = find.byKey(const ValueKey('genai-image-parameters'));
    await _reveal(tester, parameters);
    final summary = find.descendant(of: parameters, matching: find.textContaining('方形'));
    expect(summary, findsOneWidget);
    final rich = find.descendant(of: summary, matching: find.byType(RichText));
    final style = tester.widget<RichText>(rich).text.style!;
    expect(style.fontWeight, FontWeight.w600);
    expect(style.fontSize, 12);
    expect(tester.getRect(parameters).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview and description dialogs follow the draft geometry and metadata',
      (tester) async {
    debugNetworkImageHttpClientProvider = () => _ImageHttpClient(_png);
    _imageRequests = 0;
    await _showStudio(tester);
    await _generate(tester);
    await _openPreview(tester);

    final preview = find.byKey(const ValueKey('genai-image-preview'));
    final previewShape = tester.widget<Dialog>(preview).shape! as RoundedRectangleBorder;
    expect((previewShape.borderRadius as BorderRadius).topLeft, const Radius.circular(18));
    expect(
      tester
          .widget<SelectableText>(
            find.descendant(of: preview, matching: find.byType(SelectableText)),
          )
          .contextMenuBuilder,
      genAiTextSelectionContextMenu,
    );
    final header = tester.widget<Padding>(
      find.byKey(const ValueKey('genai-preview-header')),
    );
    expect(header.padding, const EdgeInsets.fromLTRB(22, 18, 22, 18));
    expect(
      tester.getSize(find.byKey(const ValueKey('genai-preview-header'))).height,
      72,
    );
    final footer = tester.widget<Padding>(
      find.byKey(const ValueKey('genai-preview-footer')),
    );
    expect(footer.padding, const EdgeInsets.fromLTRB(18, 14, 18, 18));
    for (final tooltip in ['复制链接', '分享图片', '下载图片']) {
      expect(tester.getSize(find.byTooltip(tooltip)), const Size(36, 36));
    }
    final actionsRow = tester.widget<Row>(
      find.ancestor(of: find.byTooltip('复制链接'), matching: find.byType(Row)).first,
    );
    expect(actionsRow.spacing, 6);
    expect(
      tester.getSize(find.byKey(const ValueKey('genai-preview-more'))),
      const Size(36, 36),
    );

    // The more menu opens entirely above the 36px anchor with an 8px gap,
    // right-aligned to it, even when the centered dialog leaves room below.
    await tester.tap(find.byTooltip('更多图片操作'));
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('genai-anchored-menu'));
    expect(menu, findsOneWidget);
    final anchorRect = tester.getRect(find.byKey(const ValueKey('genai-preview-more')));
    final menuRect = tester.getRect(menu);
    expect(menuRect.width, 170);
    expect(menuRect.right, closeTo(anchorRect.right, 1));
    expect(menuRect.bottom, closeTo(anchorRect.bottom - 44, 1));
    expect(menuRect.bottom, lessThan(anchorRect.top));
    final menuMaterial = tester.widget<Material>(menu);
    expect(
      (menuMaterial.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(9),
    );

    await tester.tap(find.text('查看描述'));
    await tester.pumpAndSettle();
    final description = find.byKey(const ValueKey('genai-image-description'));
    expect(description, findsOneWidget);
    expect(tester.getSize(description).width, isPositive);
    expect(
      tester.getSize(find.byKey(const ValueKey('genai-description-surface'))).width,
      closeTo(500, 1),
    );
    final descriptionShape =
        tester.widget<GenAiDialogFrame>(description).shape! as RoundedRectangleBorder;
    expect(
      (descriptionShape.borderRadius as BorderRadius).topLeft,
      const Radius.circular(18),
    );
    final descriptionHeader = tester.widget<Padding>(
      find.byKey(const ValueKey('genai-description-header')),
    );
    expect(descriptionHeader.padding, const EdgeInsets.fromLTRB(22, 18, 22, 18));
    expect(
      tester.getSize(find.byKey(const ValueKey('genai-description-header'))).height,
      72,
    );
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(
      find.descendant(of: description, matching: find.byType(Divider)),
      findsWidgets,
    );
    expect(
      find.descendant(of: description, matching: find.text('描述')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: description, matching: find.text('Studio geometry check')),
      findsNWidgets(2),
    );
    // The draft's description dialog has no image preview.
    expect(
      find.descendant(of: description, matching: find.byType(Image)),
      findsNothing,
    );
    final body = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('genai-description-body')),
    );
    expect(body.padding, const EdgeInsets.all(17));
    final selectables = tester.widgetList<SelectableText>(
      find.descendant(of: description, matching: find.byType(SelectableText)),
    );
    expect(selectables, isNotEmpty);
    expect(
      selectables.every(
        (text) => text.contextMenuBuilder == genAiTextSelectionContextMenu,
      ),
      isTrue,
    );
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
    // The shared fixture's history rows carry no metadata, so no quality row.
    expect(
      find.descendant(of: description, matching: find.text('质量')),
      findsNothing,
    );
    await tester.tap(find.text('返回图片'));
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);
    // Painting debug variables must be restored before the binding checks
    // invariants at the end of the test body.
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    expect(tester.takeException(), isNull);
  });

  testWidgets('studio text fields expose the GenAI selection menu', (tester) async {
    await _showStudio(tester);
    final prompt = find.byKey(const ValueKey('genai-image-prompt'));
    expect(tester.widget<TextField>(prompt).contextMenuBuilder, genAiTextSelectionContextMenu);
    final resolution = find.byKey(const ValueKey('genai-image-resolution'));
    await tester.ensureVisible(resolution);
    await tester.tap(resolution);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('genai-image-width'))).contextMenuBuilder,
      genAiTextSelectionContextMenu,
    );
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('genai-image-height'))).contextMenuBuilder,
      genAiTextSelectionContextMenu,
    );
  });

  testWidgets('known quality metadata renders in the description', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeGenAiServer(chunkDelay: Duration.zero);
    final historyGate = Completer<void>();
    final transport = ScriptedTransport((request) async {
      if (request.uri.path == '/htk/ai-image-history/list') await historyGate.future;
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
    final sessions = GenAiSessionService(api: api, store: MemorySessionStore());
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
    addTearDown(() {
      workspace.dispose();
      chat.dispose();
      sessions.dispose();
      backend.dispose();
    });
    await workspace.reloadModels();
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(workspace: workspace, initialTab: 1, stageWidth: 1200),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The history list stays blocked so the freshly generated pending record
    // (which carries the requested quality) is what the preview opens. Do not
    // settle: the loading indicator keeps animating while the list is blocked.
    await tester.enterText(
      find.byKey(const ValueKey('genai-image-prompt')),
      'Known quality',
    );
    await tester.pump();
    final generate = find.byKey(const ValueKey('genai-image-generate'));
    await tester.ensureVisible(generate);
    await tester.pump();
    await tester.tap(generate);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('生成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final gallery = find.byType(GenAiImageGallery);
    expect(gallery, findsOneWidget);
    final tile = find.descendant(of: gallery, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('genai-image-preview')), findsOneWidget);
    await tester.tap(find.byTooltip('更多图片操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('查看描述'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final description = find.byKey(const ValueKey('genai-image-description'));
    expect(description, findsOneWidget);
    expect(
      find.descendant(of: description, matching: find.text('质量')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: description, matching: find.text('普通')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage width drives breakpoints inside a sidebar-narrowed box', (tester) async {
    // 1280 window with an open 232px sidebar leaves 1048px of local space.
    await _showStudio(
      tester,
      size: const Size(1280, 900),
      stageWidth: 1280,
      localWidth: 1048,
    );
    final form = find.byKey(const ValueKey('genai-image-form'));
    expect(tester.getSize(form).width, 290);
    expect(tester.getSize(find.byKey(const ValueKey('genai-image-gap'))).width, 42);
    expect(
      tester.widget<Padding>(find.byKey(const ValueKey('genai-image-padding'))).padding,
      const EdgeInsets.fromLTRB(32, 24, 32, 40),
    );
    expect(tester.takeException(), isNull);

    // A 1100px stage stays in the compact desktop geometry even when the
    // local box is narrower than the stage.
    await _showStudio(
      tester,
      size: const Size(1100, 900),
      stageWidth: 1100,
      localWidth: 868,
    );
    expect(tester.getSize(form).width, 255);
    expect(tester.getSize(find.byKey(const ValueKey('genai-image-gap'))).width, 26);
    expect(
      tester.widget<Padding>(find.byKey(const ValueKey('genai-image-padding'))).padding,
      const EdgeInsets.all(20),
    );
    expect(tester.takeException(), isNull);

    // A zero/unknown stage falls back to the window width, never to a
    // zero-width desktop layout.
    await _showStudio(tester, size: const Size(390, 900), stageWidth: 0);
    expect(find.byKey(const ValueKey('genai-image-parameters')), findsOneWidget);
  });
}

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
