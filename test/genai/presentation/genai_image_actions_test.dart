import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_image_actions.dart';

Future<Uint8List> _picture(int width) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, 24);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

final class _TemporaryClipboard extends IOOverrides {
  _TemporaryClipboard(this.directory);
  final Directory directory;

  @override
  Directory getSystemTempDirectory() => directory;
}

void main() {
  for (final mobile in [true, false]) {
    testWidgets(
        '${mobile ? 'menu button' : 'right click'} copies the selected image, not its neighbor',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = mobile ? const Size(320, 740) : const Size(1280, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final images = await tester.runAsync(() async => [await _picture(16), await _picture(32)]);
      final temporary = Directory.systemTemp.createTempSync('genai-clipboard-test-');
      final previousOverrides = IOOverrides.current;
      IOOverrides.global = _TemporaryClipboard(temporary);
      addTearDown(() {
        IOOverrides.global = previousOverrides;
        temporary.deleteSync(recursive: true);
      });
      var copied = Completer<Uint8List>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('pasteboard'),
        (call) async {
          if (call.method == 'writeImage') {
            final value = call.arguments;
            copied.complete(
              value is Uint8List
                  ? value
                  : await File((value as Map<Object?, Object?>)['fileName']! as String)
                      .readAsBytes(),
            );
          } else if (call.method == 'writeFiles') {
            final paths = call.arguments as List<Object?>;
            copied.complete(await File(paths.single! as String).readAsBytes());
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('pasteboard'),
          null,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (var i = 0; i < 2; i++)
                  GenAiImageActions(
                    key: ValueKey(i),
                    image: MemoryImage(images![i]),
                    child: SizedBox(width: 240, height: 160, child: Image.memory(images[i])),
                  ),
              ],
            ),
          ),
        ),
      );
      for (final i in [1, 0]) {
        final target = find.byKey(ValueKey(i));
        await tester.runAsync(() => precacheImage(MemoryImage(images![i]), tester.element(target)));
        await tester.pumpAndSettle();
        final tile = tester.getRect(target);
        if (mobile) {
          await tester.longPress(target);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('genai-anchored-menu')), findsNothing);
          await tester.tap(find.descendant(of: target, matching: find.byTooltip('图片操作')));
        } else {
          await tester.tapAt(tester.getCenter(target), buttons: kSecondaryMouseButton);
        }
        // Image encoding is a real engine operation, outside the fake clock.
        await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pumpAndSettle();
        final surface = find.byKey(ValueKey(mobile ? 'genai-choice-sheet' : 'genai-anchored-menu'));
        expect(surface, findsOneWidget);
        if (!mobile) {
          final menu = tester.getRect(surface);
          expect(menu.overlaps(tile), isFalse);
          expect(menu.top - tile.bottom == 7 || tile.top - menu.bottom == 7, isTrue);
        }
        final action = find.ancestor(
          of: find.text(Platform.isLinux ? '复制图片文件' : '复制图片'),
          matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        );
        expect(action, findsOneWidget);
        expect(tester.widget<PopupMenuItem<dynamic>>(action).enabled, isTrue);
        expect(tester.getRect(action).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(action).right, lessThanOrEqualTo(tester.view.physicalSize.width));
        final png = await tester.runAsync(() async {
          await tester.tap(action);
          await tester.pump();
          return copied.future.timeout(const Duration(seconds: 5));
        });
        await tester.pumpAndSettle();
        expect(ByteData.sublistView(png!).getUint32(16), i == 0 ? 16 : 32);
        copied = Completer<Uint8List>();
        expect(surface, findsNothing);
        expect(tester.takeException(), isNull);
      }
      // A click anchors the visible button itself, and Escape dismisses it.
      final button = find.byTooltip('图片操作').first;
      final buttonRect = tester.getRect(button);
      await tester.tap(button);
      await tester.pump();
      final buttonSurface =
          find.byKey(ValueKey(mobile ? 'genai-choice-sheet' : 'genai-anchored-menu'));
      expect(buttonSurface, findsOneWidget);
      if (!mobile) expect(tester.getRect(buttonSurface).overlaps(buttonRect), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(buttonSurface, findsNothing);
    });
  }

  testWidgets('gallery tile menu anchors outside the whole tile', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final png = (await tester.runAsync(() => _picture(16)))!;
    final image = MemoryImage(png);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: GenAiImageActions(
                image: image,
                link: Uri.parse('https://example.test/gallery.png'),
                showMenuButton: false,
                onOpen: () {},
                onReference: () {},
                child: SizedBox(width: 240, height: 160, child: Image.memory(png)),
              ),
            ),
          ),
        ),
      ),
    );
    final target = find.byType(GenAiImageActions);
    await tester.runAsync(() => precacheImage(image, tester.element(target)));
    await tester.pumpAndSettle();
    // Gallery tiles leave the visible affordance to their preview.
    expect(find.byTooltip('图片操作'), findsNothing);
    final tile = tester.getRect(target);
    await tester.tapAt(tester.getCenter(target), buttons: kSecondaryMouseButton);
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('genai-anchored-menu'));
    expect(surface, findsOneWidget);
    expect(find.text('查看图片'), findsOneWidget);
    expect(find.text('用作参考'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    // The anchor is the tile itself, so the popover never covers the image.
    final menu = tester.getRect(surface);
    expect(menu.overlaps(tile), isFalse);
    expect(menu.top - tile.bottom == 7 || tile.top - menu.bottom == 7, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(surface, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('share helper checks the caller scope before sharing or copying', (tester) async {
    final png = (await tester.runAsync(() => _picture(16)))!;
    var clipboardWrites = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardWrites++;
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: Text('share host'));
          },
        ),
      ),
    );
    // A stale scope must return before either effect runs; on a platform that
    // cannot share, an ignored guard would have written the link to the
    // clipboard, and on one that can it would have invoked the share channel.
    await tester.runAsync(
      () => shareGenAiImagePng(
        image: MemoryImage(png),
        context: hostContext,
        link: Uri.parse('https://example.test/image.png'),
        isCurrent: () => false,
      ),
    );
    await tester.pumpAndSettle();
    expect(clipboardWrites, 0);
    expect(tester.takeException(), isNull);
  });
}
