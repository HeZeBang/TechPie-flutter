import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
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
          final search = tester.getSemantics(find.byType(TextField).first);
          expect(search.rect.width, lessThanOrEqualTo(240));
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
      expect(actual.inputDecorationTheme, expected.inputDecorationTheme);
      expect(actual.dialogTheme, expected.dialogTheme);
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
      if (wide) {
        final account = find.byTooltip('GenAI 账户');
        expect(account, findsOneWidget);
        expect(find.byKey(_compactNew), findsNothing);
        expect(
          tester.getRect(fresh).right,
          lessThan(tester.getRect(model).left),
        );
      } else if (scenario.size.width >= 560 && scenario.size.width > scenario.size.height) {
        expect(find.byKey(_wideNew), findsNothing);
        expect(
          tester.getRect(model).top,
          greaterThanOrEqualTo(tester.getRect(find.byKey(_prompt)).bottom),
        );
      } else {
        expect(find.byKey(_wideNew), findsNothing);
        final modelBounds = tester.getRect(model);
        final newBounds = tester.getRect(fresh);
        expect(newBounds.left, greaterThanOrEqualTo(modelBounds.right));
        expect(
          (newBounds.center.dy - modelBounds.center.dy).abs(),
          lessThan(12),
        );
        expect(
          newBounds.top,
          greaterThan(tester.getRect(find.byTooltip('GenAI 账户')).bottom),
        );
      }

      final prompt = find.byKey(_prompt);
      await _reachable(tester, prompt, viewport);
      await tester.enterText(prompt, '保留我的草稿');
      await tester.pumpAndSettle();
      final thinking = find.byKey(_thinking);
      final campus = find.byKey(_campus);
      for (final entry in [
        (thinking, 'genai-thinking-menu-toggle'),
        (campus, 'genai-agent-menu-toggle'),
      ]) {
        if (entry.$1.evaluate().isNotEmpty) {
          await _reachable(tester, entry.$1, viewport);
          expect(tester.getSize(entry.$1).height, greaterThanOrEqualTo(48));
        } else {
          await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
          await tester.pumpAndSettle();
          final menuItem = find.byKey(ValueKey(entry.$2));
          await _reachable(tester, menuItem, viewport);
          if (scenario.keyboard > 0) {
            await tester.tap(menuItem);
            await tester.pumpAndSettle();
            await _reachable(tester, entry.$1, viewport);
            expect(tester.widget<FilterChip>(entry.$1).selected, isTrue);
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
      await _reachable(tester, contextStatus, viewport);
      final contextBounds = tester.getRect(contextStatus);
      final audioBounds = tester.getRect(audio);
      expect(contextBounds.right, lessThanOrEqualTo(audioBounds.left));
      expect(contextBounds.center.dy, audioBounds.center.dy);
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
    expect(thinking, findsOneWidget);
    expect(campus, findsNothing);
    expect(tester.getCenter(more).dy, tester.getCenter(thinking).dy);
    expect(
      tester.getCenter(thinking).dy,
      tester.getCenter(find.byKey(const ValueKey('genai-send'))).dy,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('genai-thinking-menu-toggle')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('genai-agent-menu-toggle')));
    await tester.pumpAndSettle();
    expect(demo.workspace.agentEnabled, isTrue);
    expect(campus, findsOneWidget);
    expect(tester.widget<FilterChip>(campus).selected, isTrue);
    expect(
      tester.widget<TextField>(find.byKey(_prompt)).controller!.text,
      '保留草稿',
    );
    demo.workspace.setThinking(true);
    tester.view.physicalSize = const Size(320, 740);
    await tester.pumpAndSettle();
    expect(thinking, findsOneWidget);
    expect(campus, findsOneWidget);
    expect(tester.widget<FilterChip>(thinking).selected, isTrue);
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
}
