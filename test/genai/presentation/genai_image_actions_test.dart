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
        '${mobile ? 'long press' : 'right click'} copies the selected image, not its neighbor',
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
        if (mobile) {
          await tester.longPress(target);
        } else {
          await tester.tapAt(tester.getCenter(target), buttons: kSecondaryMouseButton);
        }
        // Image encoding is a real engine operation, outside the fake clock.
        await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pumpAndSettle();
        final action = find.widgetWithText(MenuItemButton, Platform.isLinux ? '复制图片文件' : '复制图片');
        expect(tester.widget<MenuItemButton>(action).onPressed, isNotNull);
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
        expect(find.byType(MenuItemButton), findsNothing);
        expect(tester.takeException(), isNull);
      }
      // Keyboard users can dismiss a pointer-opened menu and return to its button.
      await tester.tap(find.byTooltip('图片操作').first);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
    });
  }
}
