import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/presentation/genai_composer.dart';
import 'package:techpie/features/genai/presentation/genai_icons.dart';
import 'package:techpie/features/genai/presentation/genai_model_picker.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/theme_service.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

const _prompt = ValueKey('genai-prompt');
const _thinking = ValueKey('genai-thinking-toggle');
const _campus = ValueKey('genai-agent-toggle');
const _compactNew = ValueKey('genai-new-chat-compact');
const _wideNew = ValueKey('genai-new-chat-wide');
const _more = ValueKey('genai-composer-more');

Future<TestGenAiWorkspace> _show(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  double keyboard = 0,
  EdgeInsets safeArea = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
  addTearDown(demo.dispose);
  demo.workspace.configureAgent(
    runner: GenAiAgentRunner(
      tools: () => GenAiAgentToolRegistry([]),
      streamChat: (_, __) async* {
        yield const GenAiTextDelta('本地布局测试');
        yield const GenAiChatFinished(GenAiFinishReason.stop);
      },
    ),
  );
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
          padding: safeArea,
          viewPadding: safeArea,
        ),
        child: child!,
      ),
      home: const Scaffold(body: Text('TechPie host')),
    ),
  );
  // The real module is pushed from TechPie. Include its back button in the
  // available-width budget instead of testing an unrealistically empty header.
  unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => GenAiWorkspace(
          controller: demo.workspace,
          audioRecorder: FakeGenAiAudioRecorder(),
          login: (_) async => null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return demo;
}

Future<void> _reachable(
  WidgetTester tester,
  Finder control,
  Rect viewport,
) async {
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  expect(control.hitTestable(), findsOneWidget);
  final bounds = tester.getRect(control);
  expect(viewport.contains(bounds.center), isTrue);
  expect(bounds.left, greaterThanOrEqualTo(viewport.left - .5));
  expect(bounds.right, lessThanOrEqualTo(viewport.right + .5));
  expect(bounds.top, greaterThanOrEqualTo(viewport.top - .5));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + .5));
  expect(tester.takeException(), isNull);
}

/// Phone modes are keyed Semantics toggles; desktop modes key the draft's
/// Material surface, whose toggled state lives on the wrapping Semantics.
bool _modeSelected(WidgetTester tester, Finder finder) {
  final widget = tester.widget(finder);
  if (widget is Semantics) return widget.properties.toggled ?? false;
  final semantics = find.ancestor(of: finder, matching: find.byType(Semantics)).first;
  return tester.widget<Semantics>(semantics).properties.toggled ?? false;
}

/// The shared anchored menu surface, measured directly from its Material.
Rect _popupMenuRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('genai-anchored-menu')));

/// Direct composer fixture: a phone composer pinned at the top of the screen
/// leaves room below the "+" control, while the workspace tests place it at
/// the bottom where the menu must open above.
Future<List<String>> _pumpComposer(
  WidgetTester tester, {
  required Size size,
  Alignment alignment = Alignment.topCenter,
  bool thinking = false,
  bool agent = false,
  bool supportsThinking = true,
  bool agentAvailable = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final actions = <String>[];
  final draft = TextEditingController();
  final focus = FocusNode();
  addTearDown(draft.dispose);
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: alignment,
          child: GenAiComposer(
            draft: draft,
            inputFocus: focus,
            hint: '输入消息',
            wide: false,
            workspaceWidth: size.width,
            keyboardOpen: false,
            sending: false,
            thinkingEnabled: thinking,
            supportsThinking: supportsThinking,
            agentAvailable: agentAvailable,
            agentEnabled: agent,
            recognizingAudio: false,
            attachments: const <GenAiAttachment>[],
            hasPendingUploads: false,
            hasFailedUploads: false,
            canSubmit: true,
            supportsRecording: true,
            supportsAudio: false,
            supportsDocuments: true,
            recording: false,
            startingRecording: false,
            recordingSeconds: 0,
            onSend: () {},
            onStop: () {},
            onThinkingChanged: (_) {},
            onAgentChanged: (_) {},
            onMenuAction: actions.add,
            onPickAudio: () {},
            onStartRecording: () {},
            onStopRecording: () {},
            onCancelRecording: () {},
            onRetryAttachment: (_) {},
            onRemoveAttachment: (_) {},
            onPreviewAttachment: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return actions;
}

/// A real long campus model name, used to prove the picker is measured rather
/// than clamped to an old per-tier cap.
const _longModel = GenAiModel(
  name: 'Kimi-K2.5-Thinking-Preview-0905',
  aiType: 'kimi-k2',
  rootAiType: 'kimi',
  payType: 'FREE',
  enableDeepThink: true,
);

const _shortModel = GenAiModel(
  name: 'Short',
  aiType: 'short',
  rootAiType: 'kimi',
  payType: 'PAID',
);

Future<List<GenAiModel>> _pumpModelPicker(
  WidgetTester tester, {
  required double width,
  GenAiModel selected = _longModel,
}) async {
  final picked = <GenAiModel>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: GenAiModelPicker(
              models: const [_longModel, _shortModel],
              selected: selected,
              loading: false,
              enabled: true,
              onSelected: picked.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return picked;
}

/// The laid-out paragraph behind a [Text], used to prove a label was neither
/// ellipsized nor allowed to overflow its row.
RenderParagraph _paragraphFor(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );

void main() {
  testWidgets('selectable text and model controls cannot cover the chat with semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final size in [const Size(390, 844), const Size(1280, 900)]) {
        final demo = await _show(tester, size: size);
        final sent = demo.workspace.send('布局检查');
        await tester.pumpAndSettle();
        await sent;
        final prompt = tester.getSemantics(find.widgetWithText(SelectableText, '布局检查'));
        expect(prompt.rect.height, lessThan(100));
        final model = tester.getSemantics(find.byKey(const ValueKey('genai-model')));
        expect(model.rect.width, lessThan(size.width));
        expect(model.rect.height, lessThan(100));
        final answer = tester.getSemantics(
          find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == 'AI 回复',
          ),
        );
        expect(answer.getSemanticsData().flagsCollection.isTextField, isFalse);
        if (size.width > 960) {
          expect(find.byTooltip('搜索对话'), findsOneWidget);
          await tester.tap(find.byTooltip('搜索对话'));
          await tester.pumpAndSettle();
          final searchField = find.widgetWithText(TextField, '搜索历史对话');
          expect(searchField, findsOneWidget);
          expect(tester.getSize(searchField).width, lessThanOrEqualTo(500));
          await tester.tap(find.byTooltip('关闭'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('workspace follows live TechPie theme changes including AMOLED', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final themes = ThemeService(StorageService(await SharedPreferences.getInstance()));
    addTearDown(themes.dispose);
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    final workspace = GenAiWorkspace(
      controller: demo.workspace,
      audioRecorder: FakeGenAiAudioRecorder(),
      login: (_) async => null,
    );
    themes.updateSystemSchemes(
      ColorScheme.fromSeed(seedColor: Colors.teal),
      ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
    );
    for (final mode in [AppThemeMode.light, AppThemeMode.dark, AppThemeMode.amoled]) {
      await themes.setMode(mode);
      final expected = mode == AppThemeMode.light ? themes.lightTheme : themes.darkTheme;
      await tester.pumpWidget(MaterialApp(theme: expected, home: workspace));
      await tester.pumpAndSettle();
      final actual = Theme.of(tester.element(find.byKey(_prompt)));
      expect(actual.colorScheme, expected.colorScheme);
      expect(actual.scaffoldBackgroundColor, expected.scaffoldBackgroundColor);
      final host = Theme.of(tester.element(find.byType(GenAiWorkspace)));
      expect(actual.textTheme, host.textTheme);
      // GenAI adds its own component shapes, derived from the live scheme.
      // GenAI adds its own component shapes; their colours follow the live scheme.
      final palette = GenAiPalette.of(tester.element(find.byKey(_prompt)));
      final focused = actual.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, expected.colorScheme.primary);
      expect(actual.inputDecorationTheme.fillColor, palette.raised);
      expect(actual.dialogTheme.backgroundColor, palette.raised);
      // Selection follows the live accent with the workspace's soft .22 tint.
      expect(actual.textSelectionTheme.selectionColor, palette.accent.withValues(alpha: .22));
      expect(actual.textSelectionTheme.cursorColor, palette.accent);
      expect(actual.textSelectionTheme.selectionHandleColor, palette.accent);
      if (mode == AppThemeMode.amoled) {
        expect(actual.colorScheme.surface, Colors.black);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('document validation stays readable and removable on a narrow screen',
      (tester) async {
    final demo = await _show(tester, size: const Size(320, 760), textScale: 1.3);
    await demo.workspace.addDocumentAttachment('presentation.pptx', [1, 2, 3]);
    await tester.pumpAndSettle();
    final attachment = demo.workspace.attachments.single;
    expect(find.textContaining(attachment.error!), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(ValueKey('genai-remove-attachment-${attachment.id}')));
    await tester.pumpAndSettle();
    expect(demo.workspace.attachments, isEmpty);
    expect(tester.takeException(), isNull);
  });

  const viewports = [
    (name: 'narrow phone', size: Size(320, 740), scale: 1.6, keyboard: 280.0),
    (
      name: 'phone with enlarged text and keyboard',
      size: Size(390, 844),
      scale: 1.6,
      keyboard: 280.0,
    ),
    (
      name: 'landscape phone with keyboard',
      size: Size(844, 390),
      scale: 1.0,
      keyboard: 140.0,
    ),
    (name: 'compact landscape large text', size: Size(568, 320), scale: 2.0, keyboard: 0.0),
    (name: 'landscape phone', size: Size(667, 375), scale: 1.0, keyboard: 0.0),
    (name: 'large landscape phone', size: Size(932, 430), scale: 1.0, keyboard: 0.0),
    (name: 'landscape enlarged text', size: Size(844, 390), scale: 2.0, keyboard: 0.0),
    (name: 'tablet', size: Size(768, 1024), scale: 1.0, keyboard: 0.0),
    (
      name: 'wide breakpoint with enlarged text',
      size: Size(960, 720),
      scale: 1.4,
      keyboard: 0.0,
    ),
    (name: 'desktop', size: Size(1440, 900), scale: 1.0, keyboard: 0.0),
  ];

  for (final scenario in viewports) {
    testWidgets('chat controls remain reachable on ${scenario.name}', (tester) async {
      final demo = await _show(
        tester,
        size: scenario.size,
        textScale: scenario.scale,
        keyboard: scenario.keyboard,
        safeArea: scenario.name == 'landscape phone with keyboard'
            ? const EdgeInsets.fromLTRB(59, 0, 59, 21)
            : EdgeInsets.zero,
      );
      final viewport = Rect.fromLTWH(
        0,
        0,
        scenario.size.width,
        scenario.size.height - scenario.keyboard,
      );
      expect(tester.takeException(), isNull);
      final semantics = tester.ensureSemantics();
      final input = tester.widget<TextField>(find.byKey(_prompt));
      final surface = find.byKey(const ValueKey('genai-composer-surface'));
      await tester.ensureVisible(surface);
      try {
        final surfaceSemantics = tester.getSemantics(surface).getSemanticsData();
        expect(surfaceSemantics.label, '输入消息');
        expect(surfaceSemantics.hasAction(SemanticsAction.tap), isTrue);
      } finally {
        semantics.dispose();
      }
      // Padding is part of the input hit area, without stealing toolbar taps.
      await tester.tapAt(tester.getTopRight(surface) + const Offset(-4, 10));
      await tester.pumpAndSettle();
      expect(input.focusNode!.hasFocus, isTrue);
      input.focusNode!.unfocus();
      await tester.pumpAndSettle();
      final model = find.byKey(const ValueKey('genai-model'));
      final wide = scenario.size.width >= 960;
      final fresh = find.byKey(wide ? _wideNew : _compactNew);
      await _reachable(tester, model, viewport);
      await _reachable(tester, fresh, viewport);
      // The model picker always lives in the composer under the prompt.
      expect(
        tester.getRect(model).top,
        greaterThanOrEqualTo(tester.getRect(find.byKey(_prompt)).bottom),
      );
      if (wide) {
        // The sidebar holds account and new chat; the header holds neither.
        expect(find.byTooltip('GenAI 账户'), findsOneWidget);
        expect(find.byKey(_compactNew), findsNothing);
        expect(tester.getRect(fresh).right, lessThan(tester.getRect(model).left));
      } else {
        // Compact screens keep new chat in the header and account in the drawer.
        expect(find.byKey(_wideNew), findsNothing);
        expect(find.byTooltip('GenAI 账户'), findsNothing);
        expect(tester.getRect(fresh).bottom, lessThan(tester.getRect(model).top));
      }

      final prompt = find.byKey(_prompt);
      await _reachable(tester, prompt, viewport);
      await tester.enterText(prompt, '保留我的草稿');
      await tester.pumpAndSettle();
      final thinking = find.byKey(_thinking);
      final campus = find.byKey(_campus);
      // The phone tier renders fixed 42px icon controls; desktop modes use the
      // draft's compact 30px Material surface instead of a Material pill.
      final phoneChips = scenario.size.width <= 680;
      for (final entry in [
        (thinking, 'genai-thinking-menu-toggle'),
        (campus, 'genai-agent-menu-toggle'),
      ]) {
        if (entry.$1.evaluate().isNotEmpty) {
          await _reachable(tester, entry.$1, viewport);
          final height = tester.getSize(entry.$1).height;
          expect(height, phoneChips ? 42.0 : 30.0);
        } else {
          await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
          await tester.pumpAndSettle();
          final menuItem = find.byKey(ValueKey(entry.$2));
          await _reachable(tester, menuItem, viewport);
          if (scenario.keyboard > 0) {
            await tester.tap(menuItem);
            await tester.pumpAndSettle();
            await _reachable(tester, entry.$1, viewport);
            expect(_modeSelected(tester, entry.$1), isTrue);
            await tester.tap(entry.$1);
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          }
          await tester.pumpAndSettle();
        }
      }
      expect(tester.widget<TextField>(prompt).controller!.text, '保留我的草稿');
      await _reachable(
        tester,
        find.byKey(const ValueKey('genai-audio-stt')),
        viewport,
      );
      await _reachable(
        tester,
        find.byKey(const ValueKey('genai-send')),
        viewport,
      );
      expect(
        tester.widget<IconButton>(find.byKey(const ValueKey('genai-send'))).onPressed,
        isNotNull,
      );
      // A completed request adds the context indicator to the trailing actions.
      // It must remain reachable beside audio even with a keyboard or large text.
      final sent = demo.workspace.send('布局检查');
      await tester.pumpAndSettle();
      await sent;
      final contextStatus = find.byKey(const ValueKey('genai-context-status'));
      final audio = find.byKey(const ValueKey('genai-audio-stt'));
      if (scenario.size.width < 360) {
        // Extra-narrow phones drop the context ring to keep controls on screen.
        expect(contextStatus, findsNothing);
      } else {
        await _reachable(tester, contextStatus, viewport);
        final contextBounds = tester.getRect(contextStatus);
        final audioBounds = tester.getRect(audio);
        expect(contextBounds.right, lessThanOrEqualTo(audioBounds.left));
        expect(contextBounds.center.dy, audioBounds.center.dy);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('inactive tools collapse before thinking and active modes stay visible',
      (tester) async {
    final demo = await _show(tester, size: const Size(320, 844));
    final more = find.byKey(const ValueKey('genai-composer-more'));
    final thinking = find.byKey(_thinking);
    final campus = find.byKey(_campus);
    await tester.enterText(find.byKey(_prompt), '保留草稿');
    // At 320 the toolbar is allowed to wrap instead of squeezing one row.
    expect(thinking, findsOneWidget);
    expect(campus, findsNothing);
    expect(more.hitTestable(), findsOneWidget);
    expect(thinking.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(more);
    await tester.pumpAndSettle();
    // The "+" menu always lists both modes, even while their toolbar
    // controls are visible; the check reflects the current state.
    expect(
      find.byKey(const ValueKey('genai-thinking-menu-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('genai-thinking-menu-check')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('genai-agent-menu-toggle')));
    await tester.pumpAndSettle();
    expect(demo.workspace.agentEnabled, isTrue);
    expect(campus, findsOneWidget);
    expect(_modeSelected(tester, campus), isTrue);
    expect(
      tester.widget<TextField>(find.byKey(_prompt)).controller!.text,
      '保留草稿',
    );
    demo.workspace.setThinking(true);
    tester.view.physicalSize = const Size(320, 740);
    await tester.pumpAndSettle();
    expect(thinking, findsOneWidget);
    expect(campus, findsOneWidget);
    expect(_modeSelected(tester, thinking), isTrue);
    expect(tester.takeException(), isNull);
    await tester.tap(campus);
    await tester.pumpAndSettle();
    expect(campus, findsNothing);
    expect(thinking, findsOneWidget);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(campus, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone 375 keeps new chat, plus tools and turn actions usable', (tester) async {
    final demo = await _show(tester, size: const Size(375, 812));
    final viewport = const Rect.fromLTWH(0, 0, 375, 812);
    expect(tester.takeException(), isNull);
    // Compact header retains a direct new-chat button.
    await _reachable(tester, find.byKey(_compactNew), viewport);
    expect(find.byKey(_wideNew), findsNothing);
    // Inactive campus tools stay out of the toolbar but are reachable via "+".
    expect(find.byKey(_campus), findsNothing);
    final more = find.byKey(_more);
    await _reachable(tester, more, viewport);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await _reachable(
      tester,
      find.byKey(const ValueKey('genai-agent-menu-toggle')),
      viewport,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(_prompt), '手机布局');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();
    final turn = demo.workspace.turns.single;
    // Below the wide breakpoint direct editing folds into the visible menu.
    expect(find.byKey(ValueKey('genai-turn-edit-${turn.id}')), findsNothing);
    final menu = find.byKey(ValueKey('genai-turn-menu-${turn.id}'));
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    expect(menu.hitTestable(), findsOneWidget);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('编辑并重新发送'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('375 drawer search dialog uses compact inset, radius and field size', (tester) async {
    await _show(tester, size: const Size(375, 812));
    await tester.tap(find.byTooltip('打开导航与历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索对话'));
    await tester.pumpAndSettle();
    final dialogFinder = find.byType(Dialog);
    expect(dialogFinder, findsOneWidget);
    final dialog = tester.widget<Dialog>(dialogFinder);
    // Overlay routes follow the screen, not the chat column.
    expect(dialog.insetPadding, const EdgeInsets.all(12));
    final shape = dialog.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(14));
    final search = find.widgetWithText(TextField, '搜索历史对话');
    expect(search, findsOneWidget);
    final searchField = tester.widget<TextField>(search);
    expect(searchField.style?.fontSize, 16);
    expect(searchField.style?.height, 1.5);
    expect(searchField.textAlignVertical, TextAlignVertical.center);
    expect(searchField.strutStyle?.fontSize, 16);
    expect(searchField.strutStyle?.height, 1.5);
    expect(searchField.strutStyle?.forceStrutHeight, isTrue);
    final searchHint = searchField.decoration!.hintStyle!;
    expect(searchHint.fontSize, 16);
    expect(searchHint.height, 1.5);
    // Draft search field: a 1px outline with the 9px search radius.
    final searchBorder = searchField.decoration!.enabledBorder! as OutlineInputBorder;
    expect(searchBorder.borderRadius, BorderRadius.circular(9));
    expect(searchBorder.borderSide.width, 1);
    final searchRect = tester.getRect(search);
    expect(searchRect.left, greaterThanOrEqualTo(12));
    expect(searchRect.right, lessThanOrEqualTo(375 - 12));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(dialogFinder, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 phone sizes the model from its label and keeps the composer in the viewport',
      (tester) async {
    final demo = await _show(tester, size: const Size(320, 640));
    final viewport = const Rect.fromLTWH(0, 0, 320, 640);
    final model = find.byKey(const ValueKey('genai-model'));
    await _reachable(tester, model, viewport);
    final selected = demo.workspace.selectedModel!;
    final natural = GenAiModelPicker.widthFor(tester.element(model), selected.name);
    final measured = tester.getSize(model).width;
    // The old 84px tiny-tier cap is gone: the button keeps its measured width
    // until the row itself runs out, and the remaining toolbar still fits.
    expect(measured, lessThanOrEqualTo(natural + 1));
    expect(measured, greaterThanOrEqualTo(44));
    await _reachable(tester, find.byKey(const ValueKey('genai-send')), viewport);
    expect(tester.takeException(), isNull);
    final sent = demo.workspace.send('窄屏检查');
    await tester.pumpAndSettle();
    await sent;
    // Below 360 the context ring is omitted so the toolbar still fits.
    expect(find.byKey(const ValueKey('genai-context-status')), findsNothing);
    await _reachable(tester, model, viewport);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft survives mode changes and sidebar breakpoints until new chat', (tester) async {
    final demo = await _show(tester, size: const Size(768, 1024));
    await tester.enterText(find.byKey(_prompt), '我的未发送草稿');
    demo.workspace.setThinking(true);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(_prompt)).controller!.text,
      '我的未发送草稿',
    );
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(_prompt)).controller!.text, '我的未发送草稿');
    expect(demo.workspace.thinkingEnabled, isTrue);
    expect(tester.takeException(), isNull);
    // Crossing the sidebar breakpoint rebuilds both header and composer;
    // it must not reset the draft for the same conversation.
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    expect(find.byKey(_wideNew), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '图片创作'));
    await tester.pumpAndSettle();
    final backToChat = find.byTooltip('返回对话');
    expect(backToChat, findsOneWidget);
    expect(find.byKey(_prompt), findsNothing);
    expect(find.byKey(_wideNew), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('genai-image-prompt')), '保留图片草稿');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('图片创作'), findsOneWidget);
    expect(find.text('保留图片草稿'), findsOneWidget);
    await tester.tap(backToChat);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(_prompt)).controller!.text, '我的未发送草稿');
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '图片创作'));
    await tester.pumpAndSettle();
    expect(find.text('保留图片草稿'), findsOneWidget);
    await tester.tap(backToChat);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(_prompt)).controller!.text,
      '我的未发送草稿',
    );
    tester.view.physicalSize = const Size(768, 1024);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(_compactNew));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(_prompt)).controller!.text,
      isEmpty,
    );
    demo.workspace.setAgentEnabled(true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_prompt), '开始对话');
    await tester.pump();
    final editor = find.descendant(of: find.byKey(_prompt), matching: find.byType(EditableText));
    final composer = tester.state(editor);
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();
    expect(demo.workspace.turns, hasLength(1));
    expect(tester.state(editor), same(composer));
    expect(tester.widget<TextField>(find.byKey(_prompt)).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('composer modes, dots and send match the draft at 375/580/680/700/959',
      (tester) async {
    for (final width in [375.0, 580.0, 680.0, 700.0, 959.0]) {
      final demo = await _show(tester, size: Size(width, 812));
      final phone = width <= 680;
      final thinking = find.byKey(_thinking);
      final campus = find.byKey(_campus);
      expect(thinking, findsOneWidget, reason: 'width $width');
      final thinkingSize = tester.getSize(thinking);
      final sendSize = tester.getSize(find.byKey(const ValueKey('genai-send')));
      if (phone) {
        // Icon-only mode: 40 x 42 with a centred glyph and a 3px corner dot.
        expect(thinkingSize, const Size(40, 42), reason: 'width $width');
        expect(sendSize, const Size(42, 42), reason: 'width $width');
        expect(find.byType(FilterChip), findsNothing, reason: 'width $width');
        final chip = tester.getRect(thinking);
        final glyph = tester.getRect(find.byKey(const ValueKey('genai-thinking-toggle-icon')));
        expect(
          (glyph.center.dx - chip.center.dx).abs(),
          lessThanOrEqualTo(.5),
          reason: 'width $width',
        );
        expect(
          (glyph.center.dy - chip.center.dy).abs(),
          lessThanOrEqualTo(.5),
          reason: 'width $width',
        );
        // Inactive campus is out of the toolbar but stays in the "+" menu.
        expect(campus, findsNothing, reason: 'width $width');
        demo.workspace.setThinking(true);
        await tester.pumpAndSettle();
        final dot = find.byKey(const ValueKey('genai-thinking-toggle-dot'));
        expect(dot, findsOneWidget, reason: 'width $width');
        final dotRect = tester.getRect(dot);
        final activeChip = tester.getRect(thinking);
        expect(dotRect.size, const Size(3, 3), reason: 'width $width');
        expect(activeChip.right - dotRect.right, closeTo(7, .01), reason: 'width $width');
        expect(dotRect.top - activeChip.top, closeTo(6, .01), reason: 'width $width');
        await tester.tap(find.byKey(_more));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('genai-agent-menu-toggle')),
          findsOneWidget,
          reason: 'width $width',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      } else {
        // Desktop uses the draft's compact 30px Material surface, not a
        // Material FilterChip pill, and keeps the draft's 38px send.
        expect(find.byType(FilterChip), findsNothing, reason: 'width $width');
        expect(thinkingSize.height, 30.0, reason: 'width $width');
        final modeSurface = tester.widget<Material>(thinking);
        expect(
          modeSurface.borderRadius,
          BorderRadius.circular(8),
          reason: 'width $width',
        );
        final modeLabel = tester.widget<Text>(
          find.descendant(of: thinking, matching: find.text('深度思考')),
        );
        expect(modeLabel.style!.fontSize, 12, reason: 'width $width');
        expect(sendSize, const Size(38, 38), reason: 'width $width');
        expect(campus, findsOneWidget, reason: 'width $width');
        expect(_modeSelected(tester, thinking), isFalse, reason: 'width $width');
        demo.workspace.setThinking(true);
        await tester.pumpAndSettle();
        expect(_modeSelected(tester, thinking), isTrue, reason: 'width $width');
      }
      expect(tester.takeException(), isNull, reason: 'width $width');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('composer text aligns with the plus glyph at 375 and 1280', (tester) async {
    for (final width in [375.0, 1280.0]) {
      await _show(tester, size: Size(width, 900));
      final phone = width <= 680;
      final surface = tester.getRect(find.byKey(const ValueKey('genai-composer-surface')));
      final prompt = find.byKey(_prompt);
      final promptRect = tester.getRect(prompt);
      final textRect = tester.getRect(
        find.descendant(of: prompt, matching: find.byType(EditableText)),
      );
      final glyph = find.byKey(const ValueKey('genai-composer-more-icon'));
      expect(glyph, findsOneWidget, reason: 'width $width');
      final glyphRect = tester.getRect(glyph);
      // Draft surface padding (16 desktop, 10 phone) and textarea inset (4).
      final padding = phone ? 10.0 : 16.0;
      expect(promptRect.left - surface.left, closeTo(padding, 1.5), reason: 'width $width');
      expect(textRect.left - promptRect.left, closeTo(4, 1), reason: 'width $width');
      expect(
        (textRect.left - glyphRect.left).abs(),
        lessThanOrEqualTo(2),
        reason: 'width $width: text ${textRect.left}, glyph ${glyphRect.left}',
      );
      final field = tester.widget<TextField>(prompt);
      expect(field.style!.fontSize, phone ? 15.0 : 14.0, reason: 'width $width');
      expect(field.style!.height, 1.65, reason: 'width $width');
      // The draft top-aligns the input and forces one strut so the caret and
      // hint sit on the same 1.65 line box at both tiers.
      expect(field.textAlignVertical, TextAlignVertical.top, reason: 'width $width');
      final strut = field.strutStyle!;
      expect(strut.fontSize, phone ? 15.0 : 14.0, reason: 'width $width');
      expect(strut.height, 1.65, reason: 'width $width');
      expect(strut.forceStrutHeight, isTrue, reason: 'width $width');
      expect(
        field.decoration!.contentPadding,
        const EdgeInsets.symmetric(horizontal: 4),
        reason: 'width $width',
      );
      expect(
        field.decoration!.constraints,
        const BoxConstraints(minHeight: 50),
        reason: 'width $width',
      );
      final hintStyle = field.decoration!.hintStyle!;
      expect(hintStyle.fontSize, phone ? 15.0 : 14.0, reason: 'width $width');
      expect(hintStyle.height, 1.65, reason: 'width $width');
      final surfaceBox = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('genai-composer-surface')),
      );
      expect(
        surfaceBox.padding,
        phone
            ? const EdgeInsets.fromLTRB(10, 12, 10, 8)
            : const EdgeInsets.fromLTRB(16, 16, 16, 10),
        reason: 'width $width',
      );
      expect(tester.getSize(prompt).height, greaterThanOrEqualTo(50.0), reason: 'width $width');
      expect(tester.takeException(), isNull, reason: 'width $width');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('native selection popover matches the draft and reuses the copy callback',
      (tester) async {
    await _show(tester, size: const Size(900, 1000));
    final copies = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copies.add((call.arguments as Map)['text'] as String);
      }
      if (call.method == 'Clipboard.hasStrings') {
        return <String, dynamic>{'value': true};
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const text = '选择这段文字';
    await tester.enterText(find.byKey(_prompt), text);
    final field = tester.widget<TextField>(find.byKey(_prompt));
    field.controller!.selection = const TextSelection(baseOffset: 0, extentOffset: text.length);
    await tester.pump();
    final editable = tester.state<EditableTextState>(
      find.descendant(of: find.byKey(_prompt), matching: find.byType(EditableText)),
    );
    editable.toggleToolbar();
    await tester.pumpAndSettle();

    final popover = find.byKey(const ValueKey('genai-selection-popover'));
    expect(popover, findsOneWidget);
    final palette = GenAiPalette.of(tester.element(find.byKey(_prompt)));
    final surface = tester.widget<Material>(popover);
    final shape = surface.shape! as RoundedRectangleBorder;
    expect(surface.color, palette.raised);
    expect(shape.borderRadius, BorderRadius.circular(12));
    expect(shape.side.color, palette.line);
    expect(shape.side.width, 1);

    final copy = find.byKey(const ValueKey('genai-selection-copy'));
    expect(copy, findsOneWidget);
    expect(tester.getSize(copy).height, 42);
    expect(find.descendant(of: copy, matching: find.byType(GenAiIcon)), findsOneWidget);
    final label = tester.widget<Text>(find.descendant(of: copy, matching: find.byType(Text)));
    expect(label.data, 'Copy');
    expect(label.style!.fontSize, 13);
    expect(
      tester.widget<TextField>(find.byKey(_prompt)).contextMenuBuilder,
      genAiTextSelectionContextMenu,
    );

    // The row runs the same callback Flutter's own toolbar would.
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copies, [text]);
    expect(popover, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plus menu always lists both modes with state checks and draft labels',
      (tester) async {
    for (final scenario in [
      (name: 'phone', size: const Size(375, 900)),
      (name: 'desktop', size: const Size(900, 900)),
      (name: 'short landscape', size: const Size(844, 390)),
    ]) {
      final width = scenario.size.width;
      final demo = await _show(tester, size: scenario.size);
      final more = find.byKey(_more);
      await tester.tap(more);
      await tester.pumpAndSettle();

      // Attachments keep the existing labels, and both modes are always
      // listed even when their chips are already visible in the toolbar.
      final menu = find.byType(PopupMenuItem<String>);
      for (final label in ['上传文档', '上传图片', '深度思考', '校园工具', '查看可用工具']) {
        expect(
          find.descendant(of: menu, matching: find.text(label)),
          findsOneWidget,
          reason: 'width $width: $label',
        );
      }
      // The audio entry follows the same capability gate as the microphone.
      final audio = find.byKey(const ValueKey('genai-upload-audio'));
      if (audio.evaluate().isNotEmpty) {
        expect(
          find.descendant(of: audio, matching: find.text('上传音频')),
          findsOneWidget,
          reason: 'width $width: audio',
        );
      }
      expect(find.text('上传文件'), findsNothing, reason: 'width $width');
      expect(find.text('添加图片'), findsNothing, reason: 'width $width');
      expect(find.text('音频文件'), findsNothing, reason: 'width $width');

      // The popover row follows the draft: 17px sprite, 13px label and a
      // 10px gap; selection is a 17px accent check.
      final thinkingItem = find.byKey(const ValueKey('genai-thinking-menu-toggle'));
      final thinkingIcon = find.descendant(of: thinkingItem, matching: find.byType(GenAiIcon));
      expect(tester.getSize(thinkingIcon.first), const Size(17, 17), reason: 'width $width');
      final thinkingLabel = tester.widget<Text>(
        find.descendant(of: thinkingItem, matching: find.text('深度思考')),
      );
      expect(thinkingLabel.style!.fontSize, 13, reason: 'width $width');
      expect(
        thinkingLabel.style!.color,
        Theme.of(tester.element(find.byKey(_prompt))).colorScheme.onSurface,
      );
      final iconBox = tester.getRect(thinkingIcon.first);
      final labelBox = tester.getRect(
        find.descendant(of: thinkingItem, matching: find.text('深度思考')),
      );
      expect(labelBox.left - iconBox.right, closeTo(10, .5), reason: 'width $width');
      expect(
        tester.widget<PopupMenuItem<String>>(thinkingItem).height,
        42,
        reason: 'width $width',
      );
      expect(
        tester.widget<PopupMenuItem<String>>(thinkingItem).padding,
        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        reason: 'width $width',
      );
      // The draft row's 7px radius comes from the shared entry wrapper, which
      // lets the native hover highlight clip instead of painting square.
      final rowMaterial = find.ancestor(of: thinkingItem, matching: find.byType(Material)).first;
      expect(
        tester.widget<Material>(rowMaterial).borderRadius,
        BorderRadius.circular(7),
        reason: 'width $width',
      );
      expect(find.byKey(const ValueKey('genai-thinking-menu-check')), findsNothing);
      expect(find.byKey(const ValueKey('genai-agent-menu-check')), findsNothing);

      // Measured surface, not configuration: whichever side has room, the
      // shared anchored menu stays exactly 7px clear of the "+" control.
      final anchorRect = tester.getRect(more);
      final menuRect = _popupMenuRect(tester);
      expect(menuRect.overlaps(anchorRect), isFalse, reason: 'width $width');
      final below = menuRect.top >= anchorRect.bottom;
      final gap = below ? menuRect.top - anchorRect.bottom : anchorRect.top - menuRect.bottom;
      expect(
        gap,
        closeTo(7, .01),
        reason: 'width $width: ${below ? 'below' : 'above'} '
            'anchor ${anchorRect.top}-${anchorRect.bottom}, '
            'menu ${menuRect.top}-${menuRect.bottom}',
      );
      // A bottom-anchored composer with no room below must place the menu
      // above its anchor rather than clamp it over the control.
      if (scenario.name == 'short landscape') {
        expect(below, isFalse, reason: scenario.name);
        expect(
          anchorRect.top - menuRect.bottom,
          closeTo(7, .01),
          reason: '${scenario.name}: anchor ${anchorRect.top}, menu ${menuRect.bottom}',
        );
      }

      await tester.tap(thinkingItem);
      await tester.pumpAndSettle();
      expect(demo.workspace.thinkingEnabled, isTrue, reason: 'width $width');

      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('genai-thinking-menu-check')),
        findsOneWidget,
        reason: 'width $width',
      );
      expect(find.byKey(const ValueKey('genai-agent-menu-check')), findsNothing);
      // Selection adds the accent check but never recolors the leading icon.
      final selectedIcon =
          find.descendant(of: thinkingItem, matching: find.byType(GenAiIcon)).first;
      final leadingTheme = find.ancestor(of: selectedIcon, matching: find.byType(IconTheme)).first;
      expect(
        tester.widget<IconTheme>(leadingTheme).data.color,
        Theme.of(tester.element(find.byKey(_prompt))).colorScheme.onSurfaceVariant,
        reason: 'width $width',
      );

      await tester.tap(find.byKey(const ValueKey('genai-agent-menu-toggle')));
      await tester.pumpAndSettle();
      expect(demo.workspace.agentEnabled, isTrue, reason: 'width $width');

      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('genai-agent-menu-check')),
        findsOneWidget,
        reason: 'width $width',
      );
      expect(find.byKey(const ValueKey('genai-thinking-menu-check')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('anchored menu opens below with 7px clearance when space allows', (tester) async {
    await _pumpComposer(tester, size: const Size(375, 900));
    final more = find.byKey(_more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final anchorRect = tester.getRect(more);
    final menuRect = _popupMenuRect(tester);
    expect(menuRect.overlaps(anchorRect), isFalse);
    expect(menuRect.top, greaterThan(anchorRect.bottom));
    expect(menuRect.top - anchorRect.bottom, closeTo(7, .01));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('plus menu keeps unavailable modes disabled with current-state checks',
      (tester) async {
    final actions = await _pumpComposer(
      tester,
      size: const Size(375, 900),
      thinking: true,
      agent: true,
      supportsThinking: false,
      agentAvailable: false,
    );
    await tester.tap(find.byKey(_more));
    await tester.pumpAndSettle();
    for (final key in ['genai-thinking-menu-toggle', 'genai-agent-menu-toggle']) {
      final item = find.byKey(ValueKey(key));
      expect(item, findsOneWidget, reason: key);
      final row = tester.widget<PopupMenuItem<String>>(item);
      expect(row.enabled, isFalse, reason: key);
      expect(row.height, 42, reason: key);
    }
    // Current state stays visible even when the capability is unavailable.
    expect(find.byKey(const ValueKey('genai-thinking-menu-check')), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-agent-menu-check')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('genai-thinking-menu-toggle')));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('genai-agent-menu-toggle')).evaluate().isEmpty) {
      await tester.tap(find.byKey(_more));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('genai-agent-menu-toggle')));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('campus tools dialog is 500 wide, header-closed, and uses draft rows',
      (tester) async {
    for (final size in [const Size(900, 900), const Size(375, 812)]) {
      await _show(tester, size: size);
      await tester.tap(find.byKey(_more));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('genai-tool-list-menu')));
      await tester.pumpAndSettle();

      final dialog = find.byKey(const ValueKey('genai-tool-list-dialog'));
      expect(dialog, findsOneWidget, reason: '${size.width}');
      final width = size.width >= 532 ? 500.0 : size.width - 32;
      expect(
        tester.getSize(find.byKey(const ValueKey('genai-tool-list-content'))).width,
        closeTo(width, .5),
        reason: '${size.width}',
      );
      expect(
        find.descendant(of: dialog, matching: find.text('校园工具')),
        findsOneWidget,
      );
      // Closing lives in the header as an X; the draft has no bottom button.
      final close = find.byKey(const ValueKey('genai-tool-list-close'));
      expect(close, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.widgetWithText(TextButton, '关闭')),
        findsNothing,
      );
      // A full-width divider separates the header from the list.
      final dividers = find.descendant(of: dialog, matching: find.byType(Divider));
      expect(dividers, findsNWidgets(6), reason: '${size.width}');
      final headerDivider = tester.getRect(dividers.first);
      expect(
        headerDivider.top,
        greaterThan(
          tester.getRect(find.descendant(of: dialog, matching: find.text('校园工具'))).bottom,
        ),
      );

      final row = find.byKey(const ValueKey('genai-tool-row-当前时间'));
      expect(row, findsOneWidget);
      expect(
        tester.widget<Padding>(row).padding,
        const EdgeInsets.symmetric(vertical: 17),
      );
      expect(
        tester.getSize(find.descendant(of: row, matching: find.byType(GenAiIcon)).first),
        const Size(17, 17),
      );
      final title = tester.widget<Text>(find.descendant(of: row, matching: find.text('当前时间')));
      expect(title.style!.fontSize, 13);
      final description =
          tester.widget<Text>(find.descendant(of: row, matching: find.text('日期、时区')));
      expect(description.style!.fontSize, 11);

      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('long model names keep their full measured paragraph when the row has room',
      (tester) async {
    await _pumpModelPicker(tester, width: 600);
    final model = find.byKey(const ValueKey('genai-model'));
    expect(model, findsOneWidget);
    final label = find.descendant(of: model, matching: find.text(_longModel.name));
    expect(label, findsOneWidget);
    final paragraph = _paragraphFor(tester, label);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity) - .5),
    );
    // The button itself is the natural measurement, not an old 84/130/200 cap.
    final natural = GenAiModelPicker.widthFor(tester.element(model), _longModel.name);
    expect(natural, greaterThan(200));
    expect(tester.getSize(model).width, inInclusiveRange(natural - 3, natural + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('model menu clears its anchor and clips selected and hovered rows',
      (tester) async {
    final picked = await _pumpModelPicker(tester, width: 600);
    final model = find.byKey(const ValueKey('genai-model'));
    await tester.tap(model);
    await tester.pumpAndSettle();

    final anchor = tester.getRect(model);
    final menu = _popupMenuRect(tester);
    expect(menu.overlaps(anchor), isFalse);
    final selectedRow = find.byKey(const ValueKey('genai-model-kimi-k2'));
    final otherRow = find.byKey(const ValueKey('genai-model-short'));
    expect(selectedRow, findsOneWidget);
    expect(otherRow, findsOneWidget);

    Material rowSurface(Finder row) =>
        tester.widget<Material>(find.ancestor(of: row, matching: find.byType(Material)).first);
    for (final row in [selectedRow, otherRow]) {
      final item = tester.widget<PopupMenuItem<GenAiModel>>(row);
      expect(item.height, 42);
      expect(item.padding, const EdgeInsets.symmetric(horizontal: 10, vertical: 8));
      // The shared entry wrapper gives every row a clipped 7px hover surface.
      expect(rowSurface(row).borderRadius, BorderRadius.circular(7));
      expect(rowSurface(row).clipBehavior, Clip.antiAlias);
    }
    // Selection is a 17px accent check with muted cost/thinking detail.
    final check = find.descendant(of: selectedRow, matching: find.byType(GenAiIcon));
    expect(check, findsOneWidget);
    expect(tester.getSize(check), const Size(17, 17));
    final detail = tester.widget<Text>(
      find.descendant(of: selectedRow, matching: find.text('免费 · 支持深度思考')),
    );
    expect(detail.style!.fontSize, 11);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(1, 1));
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(otherRow));
    await tester.pumpAndSettle();
    expect(rowSurface(otherRow).borderRadius, BorderRadius.circular(7));
    expect(tester.takeException(), isNull);

    await tester.tap(otherRow);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-anchored-menu')), findsNothing);
    expect(picked.single.aiType, 'short');
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [(390.0, 1.0), (1280.0, 1.0), (390.0, 1.6)]) {
    final (width, textScale) = scenario;
    testWidgets('empty workspace heading is semibold at $width with scale $textScale',
        (tester) async {
      await _show(tester, size: Size(width, 900), textScale: textScale);
      final title = find.byKey(const ValueKey('genai-welcome-title'));
      expect(title, findsOneWidget);
      final rich = find.descendant(of: title, matching: find.byType(RichText));
      final style = tester.widget<RichText>(rich).text.style!;
      expect(style.fontWeight, FontWeight.w600);
      expect(style.fontVariations ?? const [], isEmpty);
      expect(style.fontSize, width == 390 ? equals(25) : inInclusiveRange(22, 28));
      expect(_paragraphFor(tester, title).didExceedMaxLines, isFalse);
      expect(tester.getRect(rich).right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);
    });
  }

  test('owned GenAI surfaces avoid stock dialog and menu controls', () {
    const files = [
      'lib/features/genai/presentation/genai_composer.dart',
      'lib/features/genai/presentation/genai_model_picker.dart',
      'lib/features/genai/presentation/genai_tools_page.dart',
      'lib/features/genai/presentation/genai_history_sidebar.dart',
      'lib/features/genai/presentation/genai_conversation_menu.dart',
      'lib/features/genai/presentation/genai_workspace.dart',
      'lib/features/genai/presentation/genai_image_gallery.dart',
      'lib/features/genai/presentation/genai_image_actions.dart',
      // Theme declares DropdownMenuThemeData; the grep targets invocations.
      'lib/features/genai/presentation/genai_theme.dart',
    ];
    final forbidden = <String, RegExp>{
      'AlertDialog': RegExp(r'\bAlertDialog\s*\('),
      'MenuAnchor': RegExp(r'\bMenuAnchor\s*\('),
      'PopupMenuButton': RegExp(r'\bPopupMenuButton\s*\('),
      'DropdownButton': RegExp(r'\bDropdownButton\s*(?:<[^>\n]+>)?\s*\('),
    };
    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final entry in forbidden.entries) {
        expect(
          entry.value.hasMatch(source),
          isFalse,
          reason: '$path must use the shared GenAI helper instead of ${entry.key}(',
        );
      }
    }
  });
}
