import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/presentation/genai_tools_page.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker.dart';

import '../support/fakes.dart';

class DeferredReferencePicker implements GenAiPicker {
  @override
  bool get supportsDocuments => false;
  @override
  bool get supportsAudio => false;
  @override
  Future<GenAiPickedFile?> pickDocument() async => null;
  @override
  Future<GenAiPickedFile?> pickAudio() async => null;
  final selected = Completer<GenAiPickedFile?>();
  @override
  Future<GenAiPickedFile?> pickImage() => selected.future;
}

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAIAAABt+uBvAAAApElEQVR4nO3QMQ0AMAzAsCEpf1ADMwZ7m8NSAEQ+d0afzvpBPECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQoM0eMcZiSiv2Au4AAAAASUVORK5CYII=',
  );
  Future<GenAiDemo> show(WidgetTester tester, GenAiPicker picker) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo = await GenAiDemo.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(
          workspace: demo.workspace,
          demo: true,
          initialTab: 1,
          picker: picker,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return demo;
  }

  Future<void> pick(WidgetTester tester) async {
    final add = find.byKey(const ValueKey('genai-add-reference'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    for (var i = 0; i < 100 && find.text('正在读取…').evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('正在读取…'), findsNothing);
  }

  testWidgets('local reference previews support four images, removal and confirmation count',
      (tester) async {
    final picker = FakeGenAiPicker(
      nextImage: GenAiPickedFile(name: 'red.png', bytes: png),
    );
    final demo = await show(tester, picker);
    for (var i = 0; i < 4; i++) {
      await pick(tester);
      expect(
        find.byKey(ValueKey('genai-reference-preview-$i')),
        findsOneWidget,
      );
    }
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('genai-add-reference')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('genai-remove-reference-0')));
    await tester.pumpAndSettle();
    expect(find.text('参考图片 · 3/4'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('genai-image-prompt')),
      'Use these reference colors',
    );
    await tester.pumpAndSettle();
    final generate = find.byKey(const ValueKey('genai-image-generate'));
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.textContaining('3 张参考图片'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    // Leaving the studio retains the complete draft, including preview bytes.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(
          workspace: demo.workspace,
          demo: true,
          initialTab: 1,
          picker: picker,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Use these reference colors'), findsOneWidget);
    expect(find.text('参考图片 · 3/4'), findsOneWidget);
    await demo.sessions.setOwner(null);
    await tester.pumpAndSettle();
    expect(find.text('添加参考图片'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('genai-reference-preview-0')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid and corrupt images are rejected and picker can recover', (tester) async {
    final picker = FakeGenAiPicker(
      nextImage: const GenAiPickedFile(name: 'fake.png', bytes: [1, 2, 3]),
    );
    await show(tester, picker);
    await pick(tester);
    expect(find.text('请选择 PNG、JPG 或 WebP 图片。'), findsOneWidget);
    picker.nextImage = GenAiPickedFile(name: 'truncated.png', bytes: png.take(12).toList());
    await pick(tester);
    expect(find.text('无法读取图片，请选择有效的 PNG、JPG 或 WebP 图片。'), findsOneWidget);
    picker.nextImage = GenAiPickedFile(name: 'valid.png', bytes: png);
    await pick(tester);
    expect(
      find.byKey(const ValueKey('genai-reference-preview-0')),
      findsOneWidget,
    );
    expect(find.text('请选择 PNG、JPG 或 WebP 图片。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final leavePage in [false, true]) {
    testWidgets(
        'late reference picker result is discarded after ${leavePage ? 'leaving page' : 'account switch'}',
        (tester) async {
      final picker = DeferredReferencePicker();
      final demo = await show(tester, picker);
      await tester.tap(find.byKey(const ValueKey('genai-add-reference')));
      await tester.pump();
      if (leavePage) {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        await demo.sessions.setOwner(null);
      }
      picker.selected.complete(GenAiPickedFile(name: 'late.png', bytes: png));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('genai-reference-preview-0')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
