import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/presentation/genai_icons.dart';
import 'package:techpie/features/genai/presentation/genai_tools_page.dart';

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

Finder studioMenu() => find.byKey(const ValueKey('genai-anchored-menu'));

Finder studioField(String key) => find.byKey(ValueKey(key));

Finder studioValue(String key) => find.byKey(ValueKey('$key-value'));

Finder studioOption(String key, int index) =>
    find.byKey(ValueKey('genai-studio-option-$key-$index'));

/// No DropdownButton or DropdownMenuItem may remain in the studio form.
Finder dropdownControls() => find.byWidgetPredicate(
      (widget) => widget is DropdownButton<dynamic> || widget is DropdownMenuItem<dynamic>,
    );

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
  return tester
      .widgetList<PopupMenuItem<dynamic>>(rows)
      .map((item) => item.value)
      .toList();
}

/// Selects [label] from a studio field's anchored menu, as a user would.
Future<void> selectStudioOption(WidgetTester tester, String key, String label) async {
  await openStudioMenu(tester, key);
  await tester.tap(find.descendant(of: studioMenu(), matching: find.text(label)).last);
  await tester.pumpAndSettle();
  expect(studioMenu(), findsNothing);
}

/// Verifies the menu is anchored exactly 7px clear of its field (below or
/// above), that every row is a 42px-tall, 10/8-padded, 13px option, and that
/// only the row whose value is [selected] carries the check icon.
Future<void> expectAnchoredMenu(
  WidgetTester tester,
  String key, {
  required Object? selected,
}) async {
  final anchor = studioField(key);
  await tester.ensureVisible(anchor);
  final anchorRect = tester.getRect(anchor);
  await openStudioMenu(tester, key);
  final menuRect = tester.getRect(studioMenu());
  expect(menuRect.overlaps(anchorRect), isFalse);
  final clearance = menuRect.top >= anchorRect.bottom
      ? menuRect.top - anchorRect.bottom
      : anchorRect.top - menuRect.bottom;
  expect(clearance, closeTo(7, .01));

  final rows = find.descendant(
    of: studioMenu(),
    matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem<dynamic>),
  );
  final items = tester.widgetList<PopupMenuItem<dynamic>>(rows).toList();
  expect(items, isNotEmpty);
  final selectedIndex = items.indexWhere((item) => item.value == selected);
  expect(selectedIndex, isNot(-1), reason: '$key should mark $selected as selected');
  for (var index = 0; index < items.length; index++) {
    final option = studioOption(key, index);
    expect(option, findsOneWidget);
    expect(items[index].height, greaterThanOrEqualTo(42));
    expect(items[index].padding, const EdgeInsets.symmetric(horizontal: 10, vertical: 8));
    expect(tester.getSize(option).height, greaterThanOrEqualTo(42));
    final text = find.descendant(of: option, matching: find.byType(Text)).first;
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.text.style?.fontSize, 13);
    final check = find.descendant(
      of: option,
      matching: find.byWidgetPredicate(
        (widget) => widget is GenAiIcon && widget.glyph == GenAiGlyph.check,
      ),
    );
    expect(check, index == selectedIndex ? findsOneWidget : findsNothing);
  }
  await dismissStudioMenu(tester);
}

/// The chosen label's text box is centred on its field anchor within ±1px.
void expectCentredOnAnchor(WidgetTester tester, Finder anchor, Finder label) {
  final anchorRect = tester.getRect(anchor);
  final labelRect = tester.getRect(label);
  expect(
    (labelRect.center.dy - anchorRect.center.dy).abs(),
    lessThanOrEqualTo(1),
    reason: 'the chosen label should be centred in its field',
  );
}

void main() {
  testWidgets('aspect ratio filters resolutions and validates linked and freeform custom sizes',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(
          workspace: demo.workspace,
          initialTab: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('genai-image-prompt')),
      'synthetic sizing check',
    );

    final parameters = find.byKey(const ValueKey('genai-image-parameters'));
    final parametersDialog = find.byKey(const ValueKey('genai-image-parameters-dialog'));
    final orientation = find.byKey(const ValueKey('genai-image-orientation'));
    final ratio = find.byKey(const ValueKey('genai-image-ratio'));
    final resolution = find.byKey(const ValueKey('genai-image-resolution'));
    final quality = find.byKey(const ValueKey('genai-image-quality'));
    final width = find.byKey(const ValueKey('genai-image-width'));
    final height = find.byKey(const ValueKey('genai-image-height'));
    final link = find.byKey(const ValueKey('genai-image-link'));
    final generate = find.byKey(const ValueKey('genai-image-generate'));

    Future<void> openParameters() async {
      await revealInStudio(tester, parameters);
      await tester.tap(parameters);
      await tester.pumpAndSettle();
      expect(parametersDialog, findsOneWidget);
      expect(find.text('图片参数'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    }

    Future<void> closeParameters() async {
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(parametersDialog, findsNothing);
    }

    Future<void> select(String key, String label) =>
        selectStudioOption(tester, key, label);

    Future<void> selectOrientation(String label) async {
      await tester.ensureVisible(orientation);
      final option = find.descendant(of: orientation, matching: find.text(label));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
    }

    // Narrow widths expose the same controls in the mobile parameters dialog,
    // not inline. Three orientations only: no free-form orientation entry.
    expect(parameters, findsOneWidget);
    await openParameters();
    expect(dropdownControls(), findsNothing);
    expect(find.descendant(of: orientation, matching: find.text('自定义')), findsNothing);
    expect(find.byKey(const ValueKey('genai-image-resolution-value')), findsOneWidget);
    expect(studioValueText(tester, 'genai-image-resolution'), '1K');
    await openStudioMenu(tester, 'genai-image-resolution');
    expect(studioMenuValues(tester), ['1K', '2K', 'custom']);
    await dismissStudioMenu(tester);
    await selectOrientation('横向');
    expect(studioValueText(tester, 'genai-image-resolution'), '1K');
    await openStudioMenu(tester, 'genai-image-resolution');
    expect(studioMenuValues(tester), ['1K', '2K', '4K', 'custom']);
    await dismissStudioMenu(tester);
    expect(tester.getTopLeft(orientation).dy, lessThan(tester.getTopLeft(ratio).dy));
    expect(tester.getTopLeft(ratio).dy, tester.getTopLeft(resolution).dy);
    expect(tester.getTopLeft(quality).dy, greaterThan(tester.getTopLeft(resolution).dy));
    expect(tester.getSize(quality).width, greaterThan(tester.getSize(ratio).width));

    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final scenario in [(320.0, 1.0), (375.0, 1.6), (1440.0, 1.0)]) {
      if (parametersDialog.evaluate().isNotEmpty) await closeParameters();
      tester.view.physicalSize = Size(scenario.$1, 900);
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
      await tester.pumpAndSettle();
      if (scenario.$1 > 680) {
        // Wide layouts keep the controls inline in the form.
        expect(parameters, findsNothing);
      } else {
        // Narrow layouts keep the mobile parameters button, and its dialog
        // owns the controls.
        expect(parameters, findsOneWidget);
        await openParameters();
        expect(find.text('图片参数'), findsOneWidget);
        expect(find.text('完成'), findsOneWidget);
      }
      await revealInStudio(tester, ratio);
      expect(studioValueText(tester, 'genai-image-ratio'), '16:9');
      expect(tester.getRect(ratio).right, lessThanOrEqualTo(scenario.$1));
      expect(tester.getTopLeft(orientation).dy, lessThan(tester.getTopLeft(ratio).dy));
      expect(tester.getTopLeft(ratio).dy, tester.getTopLeft(resolution).dy);
      expect(tester.getTopLeft(quality).dy, greaterThan(tester.getTopLeft(resolution).dy));
      expect(tester.takeException(), isNull);
      if (scenario.$1 <= 680) await closeParameters();
    }
    tester.view.physicalSize = const Size(375, 900);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpAndSettle();
    if (parametersDialog.evaluate().isNotEmpty) await closeParameters();
    await openParameters();

    await select('genai-image-resolution', '4K · 3840 × 2160');
    expect(studioValueText(tester, 'genai-image-resolution'), '4K');
    // 4K is a supported preset, not an experimental custom option.
    expect(find.text('超2K分辨率属实验性质，效果可能不稳定。'), findsNothing);
    // Custom dimensions belong to the custom resolution only.
    expect(width, findsNothing);
    expect(height, findsNothing);
    await selectOrientation('纵向');
    expect(studioValueText(tester, 'genai-image-ratio'), '9:16');
    expect(studioValueText(tester, 'genai-image-resolution'), '4K');
    await openStudioMenu(tester, 'genai-image-ratio');
    expect(studioMenuValues(tester), ['2:3', '3:4', '4:5', '9:16', '1:2', '9:21']);
    await dismissStudioMenu(tester);
    await selectOrientation('横向');
    expect(studioValueText(tester, 'genai-image-ratio'), '16:9');
    expect(studioValueText(tester, 'genai-image-resolution'), '4K');
    await selectOrientation('方形');
    expect(studioValueText(tester, 'genai-image-ratio'), '1:1');
    await openStudioMenu(tester, 'genai-image-ratio');
    expect(studioMenuValues(tester), contains('1:1'));
    await dismissStudioMenu(tester);
    expect(studioValueText(tester, 'genai-image-resolution'), '1K');
    await selectOrientation('横向');
    await select('genai-image-resolution', '4K · 3840 × 2160');
    expect(width, findsNothing);

    // Selecting 自定义 reveals the free-form dimensions. Typed values are
    // preserved across preset switches rather than being overwritten by the
    // selected preset.
    await select('genai-image-resolution', '自定义');
    await tester.ensureVisible(width);
    expect(tester.widget<TextField>(width).controller!.text, '1024');
    expect(tester.widget<TextField>(height).controller!.text, '1024');
    expect(tester.widget<IconButton>(link).tooltip, '宽高联动');
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(link).tooltip, '宽高独立');
    await tester.enterText(width, '1600');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(height).controller!.text, '1024');
    await tester.enterText(height, '1080');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(width).controller!.text, '1600');
    await select('genai-image-resolution', '4K · 3840 × 2160');
    expect(width, findsNothing);
    expect(height, findsNothing);
    expect(studioValueText(tester, 'genai-image-resolution'), '4K');
    await select('genai-image-resolution', '自定义');
    await tester.ensureVisible(width);
    expect(tester.widget<TextField>(width).controller!.text, '1600');
    expect(tester.widget<TextField>(height).controller!.text, '1080');

    // Linking snaps the height back to the selected ratio.
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(link).tooltip, '宽高联动');
    expect(tester.widget<TextField>(width).controller!.text, '1600');
    expect(tester.widget<TextField>(height).controller!.text, '900');

    // Free-form invalid sizes disable generation without an experimental or
    // quality caveat.
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
    expect(tester.widget<FilledButton>(generate).onPressed, isNull);
    expect(find.text('超2K分辨率属实验性质，效果可能不稳定。'), findsNothing);
    await tester.enterText(width, '1600');
    await tester.enterText(height, '820');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);

    await closeParameters();
    await revealInStudio(tester, generate);
    expect(
      find.descendant(of: generate, matching: find.text('生成图片')),
      findsOneWidget,
    );
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('生成 1 张图片'), findsOneWidget);
    expect(find.text('生成'), findsOneWidget);
    expect(find.text('开始生成'), findsNothing);
    expect(find.textContaining('1600x820'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      (await demo.workspace.repository.listImages(GenAiCancellation())).records,
      isEmpty,
    );
  });

  testWidgets('tools require image confirmation and show usage', (tester) async {
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(
          key: const ValueKey('images'),
          workspace: demo.workspace,
          initialTab: 1,
        ),
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
    await tester.enterText(
      find.byKey(const ValueKey('genai-image-prompt')),
      'a blue pie',
    );
    await tester.pump();
    final generate = find.byKey(const ValueKey('genai-image-generate'));
    await revealInStudio(tester, generate);
    expect(
      find.descendant(of: generate, matching: find.text('生成图片')),
      findsOneWidget,
    );
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('生成 1 张图片'), findsOneWidget);
    expect(find.text('生成'), findsOneWidget);
    expect(find.text('开始生成'), findsNothing);
    expect(find.textContaining('额度'), findsWidgets);
    expect(
      (await demo.workspace.repository.listImages(GenAiCancellation())).records,
      isEmpty,
    );
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('我的创作'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiToolsPage(
          key: const ValueKey('usage'),
          workspace: demo.workspace,
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('免费额度'), findsOneWidget);
    expect(find.textContaining('剩余 35'), findsOneWidget);
    await demo.sessions.setOwner(null);
    await tester.pumpAndSettle();
    expect(find.text('免费额度'), findsNothing);
    expect(find.textContaining('账号已切换'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('studio selects open anchored menus with full labels and centred values',
      (tester) async {
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Desktop, phone, and phone at 1.6 text scale: the anchor/menu geometry,
    // option contract, and centring must hold in both placements.
    for (final scenario in [(1440.0, 1.0), (375.0, 1.0), (375.0, 1.6)]) {
      tester.view.physicalSize = Size(scenario.$1, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('studio-${scenario.$1}-${scenario.$2}'),
          home: GenAiToolsPage(
            key: ValueKey('studio-page-${scenario.$1}-${scenario.$2}'),
            workspace: demo.workspace,
            initialTab: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('genai-image-prompt')),
        'anchored menus',
      );
      await tester.pumpAndSettle();
      expect(dropdownControls(), findsNothing);

      // The model picker is an anchored menu too; its field label carries the
      // selected model name.
      final modelField = studioField('genai-image-model');
      await revealInStudio(tester, modelField);
      final modelAnchor = tester.getRect(modelField);
      await openStudioMenu(tester, 'genai-image-model');
      expect(tester.getRect(studioMenu()).overlaps(modelAnchor), isFalse);
      expect(
        find.descendant(
          of: studioMenu(),
          matching: find.byWidgetPredicate(
            (widget) => widget is GenAiIcon && widget.glyph == GenAiGlyph.check,
          ),
        ),
        findsOneWidget,
      );
      await dismissStudioMenu(tester);
      expect(studioValue('genai-image-model'), findsOneWidget);

      final wide = scenario.$1 > 680;
      final parameters = find.byKey(const ValueKey('genai-image-parameters'));
      if (!wide) {
        await revealInStudio(tester, parameters);
        await tester.tap(parameters);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('genai-image-parameters-dialog')),
          findsOneWidget,
        );
      }

      // Landscape gives the resolution menu its 4K tier.
      final orientation = find.byKey(const ValueKey('genai-image-orientation'));
      await tester.ensureVisible(orientation);
      await tester.tap(find.descendant(of: orientation, matching: find.text('横向')));
      await tester.pumpAndSettle();

      // Every closed field is a Text label vertically centred in its anchor,
      // and every menu is 7px clear of that anchor.
      for (final key in const [
        'genai-image-ratio',
        'genai-image-resolution',
        'genai-image-quality',
      ]) {
        expect(studioValue(key), findsOneWidget);
        await tester.ensureVisible(studioField(key));
        expectCentredOnAnchor(tester, studioField(key), studioValue(key));
      }
      await expectAnchoredMenu(tester, 'genai-image-ratio', selected: '16:9');
      await expectAnchoredMenu(tester, 'genai-image-resolution', selected: '1K');
      await expectAnchoredMenu(tester, 'genai-image-quality', selected: 'low');

      // The menu spells the resolution out and must fit it unclipped; the
      // closed field keeps the compact tier label.
      await openStudioMenu(tester, 'genai-image-resolution');
      final fullLabel = find.descendant(
        of: studioMenu(),
        matching: find.text('1K · 1136 × 640'),
      );
      expect(fullLabel, findsOneWidget);
      final menuRect = tester.getRect(studioMenu());
      final labelRect = tester.getRect(fullLabel);
      final labelText = tester.widget<Text>(fullLabel);
      expect(labelText.maxLines, isNull);
      expect(labelText.overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester.renderObject<RenderParagraph>(fullLabel).didExceedMaxLines,
        isFalse,
      );
      expect(labelRect.left, greaterThanOrEqualTo(menuRect.left + 9));
      expect(labelRect.right, lessThanOrEqualTo(menuRect.right - 9));
      expect(labelRect.height, lessThanOrEqualTo(13 * scenario.$2 * 1.6));
      expect(menuRect.width, greaterThanOrEqualTo(labelRect.width + 40));
      await dismissStudioMenu(tester);
      expect(studioValueText(tester, 'genai-image-resolution'), '1K');
      expect(find.text('1K · 1136 × 640'), findsNothing);

      if (!wide) {
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('genai-image-parameters-dialog')),
          findsNothing,
        );
        final summary = find.byKey(const ValueKey('genai-image-parameter-summary'));
        expect(summary, findsOneWidget);
        final summaryText = tester.widget<Text>(summary);
        expect(
          summaryText.data ?? summaryText.textSpan?.toPlainText(),
          contains('横向 · 16:9 · 1K'),
        );
        await revealInStudio(tester, parameters);
        expectCentredOnAnchor(tester, parameters, summary);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
