import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/presentation/genai_image_studio_page.dart';
import 'package:techpie/features/genai/presentation/genai_usage_view.dart';

import '../support/workspace_server.dart';

/// Scrolls the studio form until [target] is built and visible. The form is a
/// lazy sliver in the page's CustomScrollView at narrow widths and a ListView
/// beside the gallery at wide widths, so targets past the fold have no element
/// until the right scrollable has advanced.
Future<void> revealInStudio(WidgetTester tester, Finder target) async {
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

Finder studioMenu() => find.byWidgetPredicate(
  (widget) =>
      widget.key == const ValueKey('genai-anchored-menu') ||
      widget.key == const ValueKey('genai-choice-sheet'),
);

Finder studioField(String key) => find.byKey(ValueKey(key));

Finder studioValue(String key) => find.byKey(ValueKey('$key-value'));

String? studioValueText(WidgetTester tester, String key) {
  final text = tester.widget<Text>(studioValue(key));
  return text.data ?? text.textSpan?.toPlainText();
}

/// Taps a studio field's button anchor and waits for its anchored menu.
Future<void> openStudioMenu(WidgetTester tester, String key) async {
  final field = studioField(key);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  expect(studioMenu(), findsOneWidget);
}

Future<void> dismissStudioMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(2, 2));
  await tester.pumpAndSettle();
  expect(studioMenu(), findsNothing);
}

/// The open menu's row values, read off the PopupMenuItem widgets instead of a
/// DropdownButton's item list.
List<Object?> studioMenuValues(WidgetTester tester) {
  final rows = find.descendant(
    of: studioMenu(),
    matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem<dynamic>),
  );
  return tester.widgetList<PopupMenuItem<dynamic>>(rows).map((item) => item.value).toList();
}

/// Selects [label] from a studio field's anchored menu, as a user would.
Future<void> selectStudioOption(WidgetTester tester, String key, String label) async {
  await openStudioMenu(tester, key);
  await tester.tap(find.descendant(of: studioMenu(), matching: find.text(label)).last);
  await tester.pumpAndSettle();
  expect(studioMenu(), findsNothing);
}

void main() {
  testWidgets('usage reconnects and rebinds without showing the previous account orders', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = await TestGenAiWorkspace.create();
    final second = await TestGenAiWorkspace.create();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.backend.usageRecords.add({'id': 'first', 'modelName': 'First account', 'totalUsed': 0});
    second.backend.usageRecords.add({
      'id': 'second',
      'modelName': 'Second account',
      'totalUsed': 0,
    });
    Widget view(TestGenAiWorkspace fixture) => MaterialApp(
      home: Scaffold(body: GenAiUsageView(workspace: fixture.workspace)),
    );
    await tester.pumpWidget(view(first));
    await tester.pumpAndSettle();
    expect(find.text('First account'), findsOneWidget);
    await first.sessions.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('First account'), findsNothing);
    await first.sessions.connect(const GenAiCredential(token: FakeGenAiServer.token));
    await tester.pumpAndSettle();
    expect(find.text('First account'), findsOneWidget);
    expect(first.backend.usagePages, [1, 1]);
    await tester.pumpWidget(view(second));
    await tester.pumpAndSettle();
    expect(find.text('First account'), findsNothing);
    expect(find.text('Second account'), findsOneWidget);
    await first.sessions.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('Second account'), findsOneWidget);
    await second.sessions.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('Second account'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('usage retries a failed next page without dropping previous orders', (tester) async {
    final demo = await TestGenAiWorkspace.create();
    addTearDown(demo.dispose);
    demo.backend.usageRecords.addAll(
      List.generate(11, (i) => {'id': '$i', 'modelName': 'Model $i', 'totalUsed': 0}),
    );
    demo.backend.failUsagePage = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GenAiUsageView(workspace: demo.workspace)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('加载更多'), 300);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('重试加载').hitTestable(), findsOneWidget);
    demo.backend.failUsagePage = null;
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(demo.backend.usagePages, [1, 2, 2]);
    expect(find.text('加载更多'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('aspect ratio filters resolutions and validates linked and freeform custom sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await tester.pumpWidget(MaterialApp(home: GenAiImageStudioPage(workspace: demo.workspace)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('genai-image-prompt')),
      'synthetic sizing check',
    );

    final parameters = find.byKey(const ValueKey('genai-image-parameters'));
    final parametersDialog = find.byKey(const ValueKey('genai-parameters-surface'));
    final orientation = find.byKey(const ValueKey('genai-image-orientation'));
    final width = find.byKey(const ValueKey('genai-image-width'));
    final height = find.byKey(const ValueKey('genai-image-height'));
    final link = find.byKey(const ValueKey('genai-image-link'));
    final generate = find.byKey(const ValueKey('genai-image-generate'));

    Future<void> openParameters() async {
      await revealInStudio(tester, parameters);
      await tester.tap(parameters);
      await tester.pumpAndSettle();
      expect(parametersDialog, findsOneWidget);
    }

    Future<void> closeParameters() async {
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(parametersDialog, findsNothing);
    }

    Future<void> select(String key, String label) => selectStudioOption(tester, key, label);

    Future<void> selectOrientation(String label) async {
      await tester.ensureVisible(orientation);
      final option = find.descendant(of: orientation, matching: find.text(label));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
    }

    await openParameters();
    expect(studioValueText(tester, 'genai-image-resolution'), '1K');
    await openStudioMenu(tester, 'genai-image-resolution');
    expect(studioMenuValues(tester), ['1K', '2K', 'custom']);
    await dismissStudioMenu(tester);
    await selectOrientation('横向');
    expect(studioValueText(tester, 'genai-image-resolution'), '1K');
    await openStudioMenu(tester, 'genai-image-resolution');
    expect(studioMenuValues(tester), ['1K', '2K', '4K', 'custom']);
    await dismissStudioMenu(tester);
    await select('genai-image-resolution', '4K · 3840 × 2160');
    expect(studioValueText(tester, 'genai-image-resolution'), '4K');
    // Custom dimensions belong to the custom resolution only.
    expect(width, findsNothing);
    expect(height, findsNothing);
    await selectOrientation('纵向');
    expect(studioValueText(tester, 'genai-image-ratio'), '9:16');
    expect(studioValueText(tester, 'genai-image-resolution'), '4K');
    await selectOrientation('横向');
    expect(studioValueText(tester, 'genai-image-ratio'), '16:9');
    expect(studioValueText(tester, 'genai-image-resolution'), '4K');
    await selectOrientation('方形');
    expect(studioField('genai-image-ratio'), findsNothing);
    expect(studioValueText(tester, 'genai-image-resolution'), '1K');
    await selectOrientation('横向');
    await select('genai-image-resolution', '4K · 3840 × 2160');
    expect(width, findsNothing);

    // Selecting 自定义 starts from the visible preset, so orientation and
    // dimensions stay consistent.
    await select('genai-image-resolution', '自定义');
    await tester.ensureVisible(width);
    expect(tester.widget<TextField>(width).controller!.text, '3840');
    expect(tester.widget<TextField>(height).controller!.text, '2160');
    expect(tester.widget<IconButton>(link).tooltip, '宽高联动');
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(link).tooltip, '宽高独立');
    await tester.enterText(width, '1600');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(height).controller!.text, '2160');
    await tester.enterText(height, '1080');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(width).controller!.text, '1600');
    expect(studioValueText(tester, 'genai-image-ratio'), '40:27');
    await select('genai-image-ratio', '16:9');
    await select('genai-image-resolution', '4K · 3840 × 2160');
    expect(width, findsNothing);
    expect(height, findsNothing);
    expect(studioValueText(tester, 'genai-image-resolution'), '4K');
    await select('genai-image-resolution', '自定义');
    await tester.ensureVisible(width);
    expect(tester.widget<TextField>(width).controller!.text, '3840');
    expect(tester.widget<TextField>(height).controller!.text, '2160');

    // Linking snaps the height back to the selected ratio.
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(link).tooltip, '宽高联动');
    await tester.enterText(width, '1600');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(height).controller!.text, '900');

    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.ensureVisible(width);
    await tester.enterText(width, '800abc');
    await tester.enterText(height, '820');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(width).controller!.text, '800');
    expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);
    await tester.enterText(height, '100');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);
    await tester.enterText(width, '1600');
    await tester.enterText(height, '820');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);

    await closeParameters();
    await revealInStudio(tester, generate);
    expect(find.descendant(of: generate, matching: find.text('生成图片')), findsOneWidget);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('生成 1 张图片'), findsOneWidget);
    expect(find.textContaining('1600x820'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((await demo.workspace.repository.listImages(GenAiCancellation())).records, isEmpty);
  });

  testWidgets('tools require image confirmation and show usage', (tester) async {
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiImageStudioPage(key: const ValueKey('images'), workspace: demo.workspace),
      ),
    );
    await tester.pumpAndSettle();
    await openStudioMenu(tester, 'genai-image-model');
    await tester.tap(
      find.descendant(of: studioMenu(), matching: find.textContaining('Test image')).last,
    );
    await tester.pumpAndSettle();
    expect(studioMenu(), findsNothing);
    expect(studioValueText(tester, 'genai-image-model'), 'Test image');
    await tester.enterText(find.byKey(const ValueKey('genai-image-prompt')), 'a blue pie');
    await tester.pump();
    final generate = find.byKey(const ValueKey('genai-image-generate'));
    await revealInStudio(tester, generate);
    expect(find.descendant(of: generate, matching: find.text('生成图片')), findsOneWidget);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('生成 1 张图片'), findsOneWidget);
    expect(find.textContaining('额度'), findsWidgets);
    expect((await demo.workspace.repository.listImages(GenAiCancellation())).records, isEmpty);
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('我的创作'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiUsageView(key: const ValueKey('usage'), workspace: demo.workspace),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('免费额度'), findsOneWidget);
    expect(find.text('35 剩余', findRichText: true), findsOneWidget);
    await demo.sessions.setOwner(null);
    await tester.pumpAndSettle();
    expect(find.text('免费额度'), findsNothing);
    expect(find.textContaining('请重新连接 GenAI'), findsOneWidget);
    expect(find.text('重试加载'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
