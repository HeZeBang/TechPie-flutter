import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/presentation/genai_image_gallery.dart';
import 'package:techpie/features/genai/presentation/genai_image_viewer.dart';

void main() {
  testWidgets('failed preview retries the same image and recovers in place', (tester) async {
    final frame = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(await _picture(const Size(40, 60)));
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame;
    });
    final provider = _RetryImage(frame!.image);
    addTearDown(frame.image.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenAiImageViewer(
            image: provider,
            link: Uri.parse('https://example.test/image.png'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('图片暂时无法加载'), findsOneWidget);
    expect(find.text('打开原图'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(provider.attempts, 2);
    expect(find.text('图片暂时无法加载'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed image proportions remain uncropped and reachable across viewport sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 750);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sizes = <Size>[
      const Size(60, 180),
      const Size(180, 60),
      const Size(100, 100),
      const Size(120, 160),
      const Size(320, 20),
      const Size(20, 320),
    ];
    final providers = await tester.runAsync(
      () async => <ImageProvider<Object>>[
        for (final size in sizes) MemoryImage(await _picture(size)),
      ],
    );
    final records = List.generate(
      36,
      (i) => GenAiImageRecord(
        id: '$i',
        prompt: 'Gallery image $i',
        images: [Uri.parse('https://example.test/${i % sizes.length}.png')],
      ),
    );
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scroll,
            slivers: [
              GenAiImageGallery(
                records: records,
                imageProvider: (uri) =>
                    providers![int.parse(uri.pathSegments.last.split('.').first)],
                onOpen: (record) => opened = record.id,
              ),
            ],
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(GenAiImageGallery));
    await tester.runAsync(() async {
      for (final provider in providers!) {
        await precacheImage(provider, context);
      }
    });
    await tester.pumpAndSettle();
    Finder tile(int index) => find.byKey(ValueKey('genai-image-$index'));
    Rect rect(int index) => tester.getRect(tile(index));
    final tileWidth = rect(0).width;
    expect(rect(0).height, closeTo(tileWidth * 3, .5));
    expect(rect(1).height, closeTo(tileWidth / 3, .5));
    expect(rect(3).left, closeTo(rect(1).left, .01));
    expect(rect(3).top, greaterThanOrEqualTo(rect(1).bottom));
    await tester.tap(tile(1));
    expect(opened, '1');
    final semantics = tester.ensureSemantics();
    await tester.pump();
    final imageNode = tester.getSemantics(
      find.descendant(
        of: tile(0),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == '查看图片',
        ),
      ),
    );
    expect(imageNode.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      imageNode.id,
      ui.SemanticsAction.tap,
    );
    expect(opened, '0');
    semantics.dispose();

    // A tall earlier tile must not be culled when shorter later tiles are above the viewport.
    scroll.jumpTo(rect(0).bottom - 100);
    await tester.pumpAndSettle();
    expect(tile(0), findsOneWidget);
    expect(rect(0).bottom, greaterThan(0));
    for (var i = 0; i < 3; i++) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(tile(35), findsOneWidget);
    expect(tester.takeException(), isNull);

    scroll.jumpTo(0);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(rect(0).width, lessThan(tileWidth));
    expect(rect(0).height, closeTo(rect(0).width * 3, .5));
    expect(rect(1).right, lessThanOrEqualTo(390));
    expect(rect(2).left, closeTo(rect(1).left, .01));
    expect(rect(2).top, greaterThanOrEqualTo(rect(1).bottom));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.descendant(of: tile(1), matching: find.byType(AnimatedOpacity)).first,
          )
          .opacity,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing and failed images keep usable tiles without blocking preview actions', (
    tester,
  ) async {
    final records = [
      GenAiImageRecord(
        id: 'broken',
        prompt: 'Broken image',
        images: [Uri.parse('https://demo/bad')],
      ),
      const GenAiImageRecord(id: 'empty', prompt: 'Empty record', images: []),
    ];
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              GenAiImageGallery(
                records: records,
                imageProvider: (_) => MemoryImage(Uint8List.fromList([0])),
                onOpen: (record) => opened = record.id,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('genai-image-broken')));
    expect(opened, 'broken');
    await tester.tap(find.byKey(const ValueKey('genai-image-empty')));
    expect(opened, 'empty');
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets('hover reveals captions with reduced motion=$reducedMotion', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 700);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = await tester.runAsync(
          () async => MemoryImage(await _picture(const Size(80, 80))),
        );
        final records = [
          GenAiImageRecord(
            id: '0',
            title: '晚霞',
            prompt: 'A long prompt for this artwork',
            images: [Uri.parse('https://example.test/0.png')],
          ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
                child: Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      const SliverToBoxAdapter(child: SizedBox(height: 10)),
                      GenAiImageGallery(
                        records: records,
                        imageProvider: (_) => provider!,
                        onOpen: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(GenAiImageGallery));
        await tester.runAsync(() => precacheImage(provider!, context));
        await tester.pumpAndSettle();
        final tile = find.byKey(const ValueKey('genai-image-0'));
        AnimatedOpacity caption() => tester.widget<AnimatedOpacity>(
          find.descendant(of: tile, matching: find.byType(AnimatedOpacity)).first,
        );
        AnimatedScale artwork() => tester.widget<AnimatedScale>(
          find.descendant(of: tile, matching: find.byType(AnimatedScale)).first,
        );
        expect(find.descendant(of: tile, matching: find.text('晚霞')), findsOneWidget);
        expect(caption().opacity, 0);
        expect(artwork().scale, 1);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(550, 2));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(tile));
        await tester.pumpAndSettle();
        expect(caption().opacity, 1);
        if (reducedMotion) {
          expect(artwork().scale, 1);
          expect(artwork().duration, Duration.zero);
        } else {
          expect(artwork().scale, greaterThan(1));
        }
        await mouse.moveTo(const Offset(550, 2));
        await tester.pumpAndSettle();
        expect(caption().opacity, 0);
        expect(artwork().scale, 1);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
  testWidgets('gallery tiles expose the draft context menu without a visible button', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = await tester.runAsync(
      () async => MemoryImage(await _picture(const Size(80, 80))),
    );
    final records = [
      for (var i = 0; i < 2; i++)
        GenAiImageRecord(
          id: '$i',
          prompt: 'Image $i',
          images: [Uri.parse('https://example.test/$i.png')],
        ),
    ];
    String? opened;
    String? referenced;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              GenAiImageGallery(
                records: records,
                imageProvider: (_) => provider!,
                onOpen: (record) => opened = record.id,
                onReference: (record) => referenced = record.id,
              ),
            ],
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(GenAiImageGallery));
    await tester.runAsync(() => precacheImage(provider!, context));
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('genai-image-0'));
    expect(find.byTooltip('图片操作'), findsNothing);
    final tileRect = tester.getRect(tile);
    await tester.tapAt(tester.getCenter(tile), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('genai-anchored-menu'));
    expect(surface, findsOneWidget);
    for (final label in ['查看图片', '用作参考', '复制链接', '保存图片']) {
      expect(find.descendant(of: surface, matching: find.text(label)), findsOneWidget);
    }
    expect(tester.getRect(surface).overlaps(tileRect), isFalse);
    await tester.tap(find.descendant(of: surface, matching: find.text('查看图片')));
    await tester.pumpAndSettle();
    expect(opened, '0');
    await tester.tapAt(tester.getCenter(tile), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('genai-anchored-menu')),
        matching: find.text('用作参考'),
      ),
    );
    await tester.pumpAndSettle();
    expect(referenced, '0');
    expect(find.byTooltip('图片操作'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _picture(Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.teal);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

class _RetryImage extends ImageProvider<_RetryImage> {
  _RetryImage(this.image);
  final ui.Image image;
  int attempts = 0;

  @override
  Future<_RetryImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_RetryImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        ++attempts == 1
            ? Future<ImageInfo>.error(StateError('temporary network failure'))
            : Future.value(ImageInfo(image: image.clone())),
      );
}
