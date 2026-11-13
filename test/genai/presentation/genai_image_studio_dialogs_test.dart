import 'dart:async';

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
import 'package:techpie/features/genai/presentation/genai_image_studio_page.dart';
import 'package:techpie/features/genai/presentation/genai_image_transfer_native.dart' as transfer;

import '../support/fakes.dart';
import '../support/image_http_client.dart';
import '../support/workspace_server.dart';

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
  Widget page = GenAiImageStudioPage(
    key: ObjectKey(demo.workspace),
    workspace: demo.workspace,
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
              .descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable))
              .first;
    await tester.scrollUntilVisible(target, 240, scrollable: scrollable);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _generate(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('genai-image-prompt')), 'Studio geometry check');
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
  testWidgets('landscape keeps generation reachable and draft survives rotation', (tester) async {
    await _showStudio(tester, size: const Size(844, 390));
    final prompt = find.byKey(const ValueKey('genai-image-prompt'));
    await tester.enterText(prompt, 'A mountain reflected in a lake');
    await tester.pump();
    final generate = find.byKey(const ValueKey('genai-image-generate'));
    expect(generate.hitTestable(), findsOneWidget);
    expect(tester.getRect(generate).bottom, lessThanOrEqualTo(390));
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(prompt).controller!.text, 'A mountain reflected in a lake');
    expect(find.byKey(const ValueKey('genai-image-parameters')), findsOneWidget);
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(prompt).controller!.text, 'A mountain reflected in a lake');
    expect(generate.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('preset request sizes come from ratio and resolution, without quota copy', (
    tester,
  ) async {
    final demo = await _showStudio(tester);

    await tester.tap(find.byKey(const ValueKey('genai-image-model')));
    await tester.pumpAndSettle();
    expect(find.textContaining('扣除额度'), findsNothing);
    expect(find.textContaining('免费'), findsNothing);
    expect(find.text('Test image'), findsWidgets);
    await tester.tap(find.text('Test image').last);
    await tester.pumpAndSettle();

    final generate = find.byKey(const ValueKey('genai-image-generate'));
    await tester.enterText(find.byKey(const ValueKey('genai-image-prompt')), 'Preset request');
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

  testWidgets('phone settings preserve custom dimensions and accessible orientation controls', (
    tester,
  ) async {
    final demo = await _showStudio(tester, size: const Size(390, 1000));

    final parameters = find.byKey(const ValueKey('genai-image-parameters'));
    expect(parameters, findsOneWidget);
    expect(find.textContaining('1:1 · 1024 × 1024'), findsOneWidget);
    await tester.tap(parameters);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-image-ratio')), findsNothing);
    for (final orientation in ['landscape', 'square', 'portrait']) {
      expect(
        tester.getSize(find.byKey(ValueKey('genai-orientation-$orientation'))).height,
        greaterThanOrEqualTo(44),
      );
    }

    // Custom fields appear only for the custom resolution, using the larger
    // tap target inside the phone dialog.
    expect(find.byKey(const ValueKey('genai-image-width')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('genai-orientation-portrait')));
    await tester.pumpAndSettle();
    final resolution = find.byKey(const ValueKey('genai-image-resolution'));
    await tester.tap(resolution);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-image-width')), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-image-height')), findsOneWidget);
    final width = tester.widget<TextField>(find.byKey(const ValueKey('genai-image-width')));
    final height = tester.widget<TextField>(find.byKey(const ValueKey('genai-image-height')));
    expect(int.parse(width.controller!.text), lessThan(int.parse(height.controller!.text)));
    final semantics = tester.ensureSemantics();
    expect(tester.getSemantics(find.byKey(const ValueKey('genai-image-width'))).label, '宽度');
    expect(tester.getSemantics(find.byKey(const ValueKey('genai-image-height'))).label, '高度');
    semantics.dispose();
    await tester.tap(find.byKey(const ValueKey('genai-orientation-landscape')));
    await tester.pumpAndSettle();
    expect(int.parse(width.controller!.text), greaterThan(int.parse(height.controller!.text)));

    await tester.tap(find.byKey(const ValueKey('genai-image-link')));
    final widthField = find.byKey(const ValueKey('genai-image-width'));
    final heightField = find.byKey(const ValueKey('genai-image-height'));
    await tester.enterText(widthField, '733');
    await tester.enterText(heightField, '511');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home: GenAiImageStudioPage(workspace: demo.workspace)));
    await tester.pumpAndSettle();
    await tester.tap(parameters);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(widthField).controller!.text, '733');
    await tester.enterText(widthField, '901');
    await tester.pump();
    expect(tester.widget<TextField>(heightField).controller!.text, '511');
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact parameter summary fits without overflow at text scale 1.6', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _showStudio(tester, size: const Size(320, 900));

    final parameters = find.byKey(const ValueKey('genai-image-parameters'));
    await _reveal(tester, parameters);
    final summary = find.descendant(of: parameters, matching: find.textContaining('1024 × 1024'));
    expect(summary, findsOneWidget);
    expect(tester.getRect(parameters).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('image preview actions remain reachable when resizing to a phone', (tester) async {
    final images = TestImageHttpClient();
    debugNetworkImageHttpClientProvider = () => images;
    await _showStudio(tester);
    await _generate(tester);
    await _openPreview(tester);

    final preview = find.byKey(const ValueKey('genai-image-preview'));
    expect(find.descendant(of: preview, matching: find.byType(InteractiveViewer)), findsOneWidget);
    expect(find.byTooltip('下载图片').hitTestable(), findsOneWidget);

    // Resizing an open preview keeps the primary action and More on one row.
    // Copy link moves into More first, followed by Share on smaller screens.
    for (final width in [320.0, 260.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      final reference = tester.getCenter(find.text('用作参考'));
      final more = find.byTooltip('更多图片操作');
      expect(tester.getCenter(more).dy, closeTo(reference.dy, 1));
      final linkInline = width == 320 && !transfer.canShareImage;
      expect(find.byTooltip('复制链接'), linkInline ? findsOneWidget : findsNothing);
      expect(tester.getCenter(find.byTooltip('下载图片')).dy, closeTo(reference.dy, 1));
      final share = find.byTooltip('分享图片');
      expect(share, width == 320 && transfer.canShareImage ? findsOneWidget : findsNothing);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('复制链接').hitTestable(), linkInline ? findsNothing : findsOneWidget);
      expect(
        find.text('分享图片'),
        width < 320 && transfer.canShareImage ? findsOneWidget : findsNothing,
      );
      expect(find.text('查看描述').hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
    }
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    expect(tester.takeException(), isNull);
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
    final api = GenAiApiClient(transport: transport, signer: const GenAiRequestSigner('synthetic'));
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
      MaterialApp(home: GenAiImageStudioPage(workspace: workspace, stageWidth: 1200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The history list stays blocked so the freshly generated pending record
    // (which carries the requested quality) is what the preview opens. Do not
    // settle: the loading indicator keeps animating while the list is blocked.
    await tester.enterText(find.byKey(const ValueKey('genai-image-prompt')), 'Known quality');
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
    expect(find.descendant(of: description, matching: find.text('质量')), findsOneWidget);
    expect(find.descendant(of: description, matching: find.text('普通')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage width drives breakpoints inside a sidebar-narrowed box', (tester) async {
    await _showStudio(tester, size: const Size(1024, 900), stageWidth: 1024, localWidth: 660);
    expect(find.byKey(const ValueKey('genai-image-form')), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-image-parameters')), findsNothing);
    expect(find.byKey(const ValueKey('genai-image-generate')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _showStudio(tester, size: const Size(390, 900), stageWidth: 0);
    expect(find.byKey(const ValueKey('genai-image-parameters')), findsOneWidget);
  });
}
