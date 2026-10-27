import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/presentation/genai_image_actions.dart';
import 'package:techpie/features/genai/presentation/genai_image_gallery.dart';

void main() {
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
                isDemo: (_) => false,
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
    expect(rect(0).height, greaterThan(rect(2).height));
    expect(rect(2).height, greaterThan(rect(1).height));
    expect(rect(4).left, closeTo(rect(1).left, .01));
    expect(rect(4).top, closeTo(rect(1).bottom + 12, .01));
    expect(
      tester.widgetList<Image>(find.byType(Image)).every((i) => i.fit == BoxFit.contain),
      isTrue,
    );
    await tester.tap(tile(1));
    expect(opened, '1');
    await tester.tap(find.descendant(of: tile(0), matching: find.byType(GenAiImageActions)));
    expect(opened, '0');
    opened = null;
    final semantics = tester.ensureSemantics();
    await tester.pump();
    final imageNode = tester.getSemantics(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '查看图片：Gallery image 0',
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
    expect(rect(1).left, closeTo(rect(0).right + 12, .01));
    expect(rect(2).left, closeTo(rect(1).left, .01));
    expect(rect(0).height, greaterThan(rect(1).height));
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
                isDemo: (_) => false,
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
