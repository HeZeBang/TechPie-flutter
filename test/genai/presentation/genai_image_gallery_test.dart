import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/presentation/genai_icons.dart';
import 'package:techpie/features/genai/presentation/genai_image_actions.dart';
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

  testWidgets('mixed image proportions remain uncropped and reachable across viewport sizes',
      (tester) async {
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
    // Tiles are the image alone: no Card, no caption row below.
    expect(find.descendant(of: tile(0), matching: find.byType(Card)), findsNothing);
    expect(rect(0).height, greaterThan(rect(2).height));
    expect(rect(2).height, greaterThan(rect(1).height));
    // Three columns at this width; the image alone sets each tile's height.
    final tileWidth = rect(0).width;
    expect(rect(0).height, closeTo(tileWidth * 3, .5));
    expect(rect(1).height, closeTo(tileWidth / 3, .5));
    expect(rect(3).left, closeTo(rect(1).left, .01));
    expect(rect(3).top, closeTo(rect(1).bottom + 17, .01));
    expect(rect(4).left, closeTo(rect(2).left, .01));
    expect(rect(4).top, closeTo(rect(2).bottom + 17, .01));
    // Wide galleries use the draft's 11px radius.
    expect(_tileRadius(tester, tile(0)), 11);
    expect(
      tester.widgetList<Image>(find.byType(Image)).every((i) => i.fit == BoxFit.contain),
      isTrue,
    );
    // The prompt is a one-line white overlay rather than a caption below.
    final caption = tester.widget<Text>(
      find.descendant(of: tile(1), matching: find.text('Gallery image 1')),
    );
    expect(caption.maxLines, 1);
    // The caption type is 10px on every layout; only spacing differs.
    expect(caption.style?.fontSize, 10);
    expect(caption.style?.color, Colors.white);
    await tester.tap(tile(1));
    expect(opened, '1');
    await tester.tap(find.descendant(of: tile(0), matching: find.byType(GenAiImageActions)));
    expect(opened, '0');
    opened = null;
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
    tester.binding.renderViews.single.owner!.semanticsOwner!
        .performAction(imageNode.id, ui.SemanticsAction.tap);
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
    expect(rect(0).width, closeTo(rect(1).width, .01));
    // The draft tightens a narrow gallery to 10px gaps, a 9px radius and a
    // 10px caption that stays visible without hover.
    expect(rect(1).left, closeTo(rect(0).right + 10, .01));
    expect(rect(2).left, closeTo(rect(1).left, .01));
    expect(rect(2).top, closeTo(rect(1).bottom + 10, .01));
    expect(rect(0).height, greaterThan(rect(1).height));
    expect(_tileRadius(tester, tile(0)), 9);
    final compactCaption = tester.widget<Text>(
      find.descendant(of: tile(1), matching: find.text('Gallery image 1')),
    );
    expect(compactCaption.style?.fontSize, 10);
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

  testWidgets('missing and failed images keep usable tiles without blocking preview actions',
      (tester) async {
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

  testWidgets(
      'tile widths follow 1280, 1600 and 800 container resizes without stale masonry widths',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = await tester.runAsync(
      () async => MemoryImage(await _picture(const Size(80, 80))),
    );
    final records = List.generate(
      6,
      (i) => GenAiImageRecord(
        id: '$i',
        prompt: 'Image $i',
        images: [Uri.parse('https://example.test/$i.png')],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              GenAiImageGallery(
                records: records,
                imageProvider: (_) => provider!,
                onOpen: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(GenAiImageGallery));
    await tester.runAsync(() => precacheImage(provider!, context));
    await tester.pumpAndSettle();
    Finder tile(int index) => find.byKey(ValueKey('genai-image-$index'));
    Future<void> expectLayout(double width, double spacing, int columns) async {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      final expected = (width - spacing * (columns - 1)) / columns;
      for (var index = 0; index < columns; index++) {
        final size = tester.getSize(tile(index));
        expect(size.width, closeTo(expected, .01));
        expect(size.height, closeTo(expected, .01));
      }
      expect(
        tester.getRect(tile(1)).left,
        closeTo(tester.getRect(tile(0)).right + spacing, .01),
      );
      // Desktop tiles use the draft's 17px vertical gap.
      expect(
        tester.getRect(tile(columns)).top,
        closeTo(tester.getRect(tile(0)).bottom + 17, .01),
      );
      expect(_tileRadius(tester, tile(0)), 11);
    }

    await expectLayout(1280, 14, 3);
    await expectLayout(1600, 14, 3);
    await expectLayout(800, 14, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 1280 stage keeps desktop gaps and corners in a narrower gallery column',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = await tester.runAsync(
      () async => MemoryImage(await _picture(const Size(80, 80))),
    );
    final records = [
      for (var i = 0; i < 3; i++)
        GenAiImageRecord(
          id: '$i',
          prompt: 'Stage image $i',
          images: [Uri.parse('https://example.test/$i.png')],
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                // The stage is 1280 wide; the gallery column itself is only 680.
                padding: const EdgeInsets.symmetric(horizontal: 300),
                sliver: GenAiImageGallery(
                  records: records,
                  stageWidth: 1280,
                  imageProvider: (_) => provider!,
                  onOpen: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(GenAiImageGallery));
    await tester.runAsync(() => precacheImage(provider!, context));
    await tester.pumpAndSettle();
    Finder tile(int index) => find.byKey(ValueKey('genai-image-$index'));
    // Two 333px columns inside the 680px sliver, separated by the desktop gap.
    expect(tester.getSize(tile(0)).width, closeTo(333, .01));
    expect(tester.getRect(tile(1)).left, closeTo(tester.getRect(tile(0)).right + 14, .01));
    expect(tester.getRect(tile(2)).top, closeTo(tester.getRect(tile(0)).bottom + 17, .01));
    expect(_tileRadius(tester, tile(0)), 11);
    final caption = tester.widget<Text>(
      find.descendant(of: tile(0), matching: find.text('Stage image 0')),
    );
    expect(caption.style?.fontSize, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a compact stage keeps 10px gaps and 9px corners in a wide column', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = await tester.runAsync(
      () async => MemoryImage(await _picture(const Size(80, 80))),
    );
    final records = [
      for (var i = 0; i < 4; i++)
        GenAiImageRecord(
          id: '$i',
          prompt: 'Compact image $i',
          images: [Uri.parse('https://example.test/$i.png')],
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              GenAiImageGallery(
                records: records,
                stageWidth: 390,
                imageProvider: (_) => provider!,
                onOpen: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(GenAiImageGallery));
    await tester.runAsync(() => precacheImage(provider!, context));
    await tester.pumpAndSettle();
    Finder tile(int index) => find.byKey(ValueKey('genai-image-$index'));
    expect(tester.getRect(tile(1)).left, closeTo(tester.getRect(tile(0)).right + 10, .01));
    expect(tester.getRect(tile(3)).top, closeTo(tester.getRect(tile(0)).bottom + 10, .01));
    expect(_tileRadius(tester, tile(0)), 9);
    final caption = tester.widget<Text>(
      find.descendant(of: tile(0), matching: find.text('Compact image 0')),
    );
    expect(caption.style?.fontSize, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('captions prefer a record title and otherwise shorten the prompt', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = await tester.runAsync(
      () async => MemoryImage(await _picture(const Size(80, 80))),
    );
    final records = [
      GenAiImageRecord(
        id: 'titled',
        title: '晚霞',
        prompt: 'a prompt that should not become the caption',
        images: [Uri.parse('https://example.test/titled.png')],
      ),
      GenAiImageRecord(
        id: 'plain',
        prompt: '湖边的日落。远处的山',
        images: [Uri.parse('https://example.test/plain.png')],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              GenAiImageGallery(
                records: records,
                imageProvider: (_) => provider!,
                onOpen: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(GenAiImageGallery));
    await tester.runAsync(() => precacheImage(provider!, context));
    await tester.pumpAndSettle();
    Finder tile(String id) => find.byKey(ValueKey('genai-image-$id'));
    expect(
      find.descendant(of: tile('titled'), matching: find.text('晚霞')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tile('titled'),
        matching: find.text('a prompt that should not become the caption'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: tile('plain'), matching: find.text('湖边的日落')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop captions reveal on hover while the artwork scales', (tester) async {
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
          prompt: 'Hover me',
          images: [Uri.parse('https://example.test/0.png')],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: false),
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
      expect(caption().opacity, 0);
      expect(artwork().scale, 1);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(550, 2));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(tile));
      await tester.pumpAndSettle();
      expect(caption().opacity, 1);
      expect(artwork().scale, 1.025);
      expect(artwork().duration, const Duration(milliseconds: 350));
      await mouse.moveTo(const Offset(550, 2));
      await tester.pumpAndSettle();
      expect(caption().opacity, 0);
      expect(artwork().scale, 1);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('reduced motion keeps the hover artwork still', (tester) async {
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
        prompt: 'Reduced motion',
        images: [Uri.parse('https://example.test/0.png')],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
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
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(550, 2));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(tile));
    await tester.pumpAndSettle();
    final artwork = tester.widget<AnimatedScale>(
      find.descendant(of: tile, matching: find.byType(AnimatedScale)).first,
    );
    expect(artwork.scale, 1);
    expect(artwork.duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery tiles expose the draft context menu without a visible button',
      (tester) async {
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
    // Native draft rows: 42 px, 10/8 px padding, and the same action set.
    final items = tester
        .widgetList<PopupMenuItem<dynamic>>(
          find.descendant(
            of: surface,
            matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
          ),
        )
        .toList();
    expect(items.length, 4);
    expect(items.every((item) => item.height == 42), isTrue);
    expect(
      items.every(
        (item) => item.padding == const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      isTrue,
    );
    for (final label in ['查看图片', '用作参考', '复制链接', '保存图片']) {
      expect(find.descendant(of: surface, matching: find.text(label)), findsOneWidget);
    }
    expect(
      items.map((item) => _menuGlyph(tester, item)),
      [GenAiGlyph.full, GenAiGlyph.image, GenAiGlyph.copy, GenAiGlyph.download],
    );
    // The whole tile is the anchor: the popover stays outside it with the
    // shared route's 7 px gap.
    final menu = tester.getRect(surface);
    expect(menu.overlaps(tileRect), isFalse);
    expect(menu.top - tileRect.bottom == 7 || tileRect.top - menu.bottom == 7, isTrue);
    // Every native row is clipped to the draft's 7 px hover plate.
    final rows = tester.widgetList<Material>(
      find.descendant(
        of: surface,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material &&
              widget.type == MaterialType.transparency &&
              widget.borderRadius == BorderRadius.circular(7),
        ),
      ),
    );
    expect(rows.length, 4);
    expect(rows.every((row) => row.clipBehavior == Clip.antiAlias), isTrue);
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

  testWidgets('masonry geometry is reused while its inputs stay unchanged', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 750);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = await tester.runAsync(
      () async => MemoryImage(await _picture(const Size(80, 80))),
    );
    final records = List.generate(
      40,
      (i) => GenAiImageRecord(
        id: '$i',
        prompt: 'Cached image $i',
        images: [Uri.parse('https://example.test/$i.png')],
      ),
    );
    Widget gallery() => MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                GenAiImageGallery(
                  records: records,
                  imageProvider: (_) => provider!,
                  onOpen: (_) {},
                ),
              ],
            ),
          ),
        );
    await tester.pumpWidget(gallery());
    final context = tester.element(find.byType(GenAiImageGallery));
    await tester.runAsync(() => precacheImage(provider!, context));
    await tester.pumpAndSettle();

    SliverGridDelegate delegate() =>
        tester.widget<SliverGrid>(find.byType(SliverGrid)).gridDelegate;
    const constraints = SliverConstraints(
      axisDirection: AxisDirection.down,
      growthDirection: GrowthDirection.forward,
      userScrollDirection: ScrollDirection.idle,
      scrollOffset: 0,
      precedingScrollExtent: 0,
      overlap: 0,
      remainingPaintExtent: 600,
      crossAxisExtent: 1100,
      crossAxisDirection: AxisDirection.right,
      viewportMainAxisExtent: 800,
      remainingCacheExtent: 800,
      cacheOrigin: 0,
    );
    final first = delegate().getLayout(constraints);
    // Repeated layout passes over the whole history reuse the cached walk.
    expect(identical(delegate().getLayout(constraints), first), isTrue);

    // A parent rebuild keeps the state-owned ratio list, so the delegate asks
    // for no relayout and the geometry stays cached.
    final oldDelegate = delegate();
    await tester.pumpWidget(gallery());
    await tester.pumpAndSettle();
    expect(delegate().shouldRelayout(oldDelegate), isFalse);
    expect(identical(delegate().getLayout(constraints), first), isTrue);

    // Scrolling only changes the scroll offset, which the walk never reads.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(identical(delegate().getLayout(constraints), first), isTrue);

    // A different cross axis is a different input and must produce new geometry.
    final narrow = delegate().getLayout(constraints.copyWith(crossAxisExtent: 800));
    expect(identical(narrow, first), isFalse);
    expect(
      first.getGeometryForChildIndex(0).crossAxisExtent,
      closeTo((1100 - 14 * 2) / 3, .01),
    );
    expect(
      narrow.getGeometryForChildIndex(0).crossAxisExtent,
      closeTo((800 - 14 * 2) / 3, .01),
    );
    expect(tester.takeException(), isNull);
  });
}

double _tileRadius(WidgetTester tester, Finder tile) => (tester
        .widget<ClipRRect>(
          find.descendant(of: tile, matching: find.byType(ClipRRect)).first,
        )
        .borderRadius as BorderRadius)
    .topLeft
    .x;

GenAiGlyph _menuGlyph(WidgetTester tester, PopupMenuItem<dynamic> item) => tester
    .widget<GenAiIcon>(
      find.descendant(of: find.byWidget(item), matching: find.byType(GenAiIcon)),
    )
    .glyph;

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
