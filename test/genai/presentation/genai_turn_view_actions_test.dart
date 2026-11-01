import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/presentation/genai_icons.dart';
import 'package:techpie/features/genai/presentation/genai_turn_view.dart';

const _turnId = 'turn-actions';

GenAiTurnActions _actions({
  void Function(String text, String message)? copy,
  void Function(int index, String action)? changeTurn,
  void Function(int index)? retry,
  VoidCallback? exportConversation,
}) =>
    GenAiTurnActions(
      copy: copy ?? (_, __) {},
      openLink: (_) {},
      changeTurn: changeTurn ?? (_, __) {},
      retry: retry ?? (_) {},
      exportConversation: exportConversation ?? () {},
      openImages: () {},
      showImage: ({Uint8List? bytes, String? url}) {},
      imageDisplayUri: (url) => Uri.parse(url),
      markdownImage: (uri, title, alt) => const SizedBox.shrink(),
      toggleTts: (_, __) {},
      approve: (_) {},
      reject: (_) {},
    );

GenAiTurnContext _context({
  required double width,
  required bool touch,
  int index = 0,
  int count = 1,
  bool sending = false,
  bool connected = true,
}) =>
    GenAiTurnContext(
      index: index,
      count: count,
      sending: sending,
      connected: connected,
      touch: touch,
      pendingApproval: null,
      latestVisual: null,
      supportsPlayback: false,
      playingTtsIndex: null,
      loadingTts: false,
      workspaceWidth: width,
    );

Widget _host({
  required double width,
  required bool touch,
  GenAiTurnActions? actions,
  int index = 0,
  int count = 1,
  bool sending = false,
  bool connected = true,
  GenAiFailure? failure,
}) {
  final turn = GenAiConversationTurn('User prompt', id: _turnId)
    ..answer = 'Answer body'
    ..failure = failure
    ..phase = failure == null ? GenAiChatPhase.completed : GenAiChatPhase.failed;
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: GenAiTurnView(
          turn: turn,
          context: _context(
            width: width,
            touch: touch,
            index: index,
            count: count,
            sending: sending,
            connected: connected,
          ),
          actions: actions ?? _actions(),
        ),
      ),
    ),
  );
}

bool _menuItemEnabled(WidgetTester tester, String label) {
  final popup = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem<String>),
  );
  return tester.widget<PopupMenuItem<String>>(popup.first).enabled;
}

Finder get _anchoredMenu => find.byKey(const ValueKey('genai-anchored-menu'));

void _sizeTo(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder get _bubble => find.byKey(const ValueKey('genai-user-bubble-$_turnId'));
Finder get _actionsRow => find.byKey(const ValueKey('genai-user-actions-$_turnId'));
Finder get _edit => find.byKey(const ValueKey('genai-turn-edit-$_turnId'));
Finder get _menu => find.byKey(const ValueKey('genai-turn-menu-$_turnId'));

void main() {
  for (final width in [375.0, 1280.0]) {
    testWidgets('campus-network warning retains the draft notice weight at $width', (tester) async {
      _sizeTo(tester, Size(width, 900));
      await tester.pumpWidget(
        _host(
          width: width,
          touch: true,
          failure: const GenAiFailure(GenAiFailureKind.campusNetworkRequired),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text('暂时无法连接校园 GenAI');
      expect(title, findsOneWidget);
      final rich = find.descendant(of: title, matching: find.byType(RichText));
      // The notice title is semibold at 600.
      expect(tester.widget<RichText>(rich).text.style?.fontWeight, FontWeight.w600);
      expect(tester.widget<RichText>(rich).text.style?.fontSize, 13);
      expect(tester.getRect(rich).right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('campus-network notice centers its icon and retry on the text block', (
    tester,
  ) async {
    _sizeTo(tester, const Size(1280, 900));
    await tester.pumpWidget(
      _host(
        width: 1280,
        touch: false,
        failure: const GenAiFailure(GenAiFailureKind.campusNetworkRequired),
      ),
    );
    await tester.pumpAndSettle();

    final icon = find.byWidgetPredicate(
      (widget) => widget is GenAiIcon && widget.glyph == GenAiGlyph.info,
    );
    expect(icon, findsOneWidget);
    final textBlock = find
        .ancestor(
          of: find.text('暂时无法连接校园 GenAI'),
          matching: find.byType(Column),
        )
        .first;
    final retry = find.byKey(const ValueKey('genai-retry-0'));
    expect(retry, findsOneWidget);

    final iconRect = tester.getRect(icon);
    final textRect = tester.getRect(textBlock);
    final retryRect = tester.getRect(retry);

    // Icon, two-line text block and retry share one vertical center, rather
    // than the icon and retry hanging off the notice's top edge.
    expect(iconRect.right, lessThan(textRect.left));
    expect(retryRect.left, greaterThan(textRect.right));
    expect(iconRect.center.dy, closeTo(textRect.center.dy, 0.01));
    expect(retryRect.center.dy, closeTo(textRect.center.dy, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('campus-network notice stacks the retry under the text on phones', (
    tester,
  ) async {
    _sizeTo(tester, const Size(375, 900));
    await tester.pumpWidget(
      _host(
        width: 375,
        touch: true,
        failure: const GenAiFailure(GenAiFailureKind.campusNetworkRequired),
      ),
    );
    await tester.pumpAndSettle();

    final subtitle = find.text('请连接校园网或校园 VPN 后重试。');
    final retry = find.byKey(const ValueKey('genai-retry-0'));
    expect(subtitle, findsOneWidget);
    expect(retry, findsOneWidget);

    final subtitleRect = tester.getRect(subtitle);
    final retryRect = tester.getRect(retry);

    // The retry keeps its own row below the copy, left-aligned with the text
    // and separated by the existing 10px gap, inside the notice width.
    expect(retryRect.top, closeTo(subtitleRect.bottom + 10, 0.01));
    expect(retryRect.left, closeTo(subtitleRect.left, 0.01));
    expect(retryRect.right, lessThanOrEqualTo(375));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact layouts keep the action row beside the bubble, bottom-aligned', (
    tester,
  ) async {
    _sizeTo(tester, const Size(390, 844));
    await tester.pumpWidget(_host(width: 390, touch: true));
    await tester.pumpAndSettle();

    final bubble = tester.getRect(_bubble);
    final actions = tester.getRect(_actionsRow);

    // The row sits to the right of the bubble with a 6px gap and shares its
    // bottom edge, rather than occupying a separate row below it.
    expect(actions.left, closeTo(bubble.right + 6, 0.01));
    expect(actions.bottom, closeTo(bubble.bottom, 0.01));
    expect(actions.top, greaterThanOrEqualTo(bubble.top));

    // Below the wide breakpoint the edit action folds into the visible menu.
    expect(_edit, findsNothing);
    expect(_menu.hitTestable(), findsOneWidget);
    expect(tester.getSize(_menu), const Size(28, 28));
  });

  testWidgets('touch layouts keep 28px actions reachable without hovering', (tester) async {
    _sizeTo(tester, const Size(1280, 900));
    await tester.pumpWidget(_host(width: 1280, touch: true));
    await tester.pumpAndSettle();

    expect(_edit, findsOneWidget);
    expect(_edit.hitTestable(), findsOneWidget);
    expect(_menu.hitTestable(), findsOneWidget);
    expect(tester.getSize(_edit), const Size(28, 28));
    expect(tester.getSize(_menu), const Size(28, 28));

    // Wide layouts still overlay the row in the fixed margin after the bubble,
    // never beside it.
    final bubble = tester.getRect(_bubble);
    final actions = tester.getRect(_actionsRow);
    expect(actions.top, closeTo(bubble.bottom + 2, 0.01));
  });

  testWidgets('desktop hover reveals actions without moving the bubble or answer', (
    tester,
  ) async {
    _sizeTo(tester, const Size(1280, 900));
    await tester.pumpWidget(_host(width: 1280, touch: false));
    await tester.pumpAndSettle();

    // Hidden actions are not laid out at all.
    expect(_actionsRow, findsNothing);
    final hiddenHeight = tester.getSize(find.byType(GenAiTurnView)).height;
    final hiddenBubble = tester.getRect(_bubble);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await tester.pump();
    await pointer.moveTo(tester.getCenter(_bubble));
    await tester.pumpAndSettle();

    expect(_actionsRow, findsOneWidget);
    expect(_edit.hitTestable(), findsOneWidget);
    expect(_menu.hitTestable(), findsOneWidget);
    expect(tester.getSize(_edit), const Size(28, 28));
    expect(tester.getSize(_menu), const Size(28, 28));

    // The actions overlay the fixed margin: nothing shifts on reveal.
    expect(tester.getRect(_bubble), hiddenBubble);
    expect(tester.getSize(find.byType(GenAiTurnView)).height, hiddenHeight);
  });

  testWidgets('answer menu opens clear of its button and keeps its actions', (tester) async {
    _sizeTo(tester, const Size(1280, 900));
    final retried = <int>[];
    final exported = <String>[];
    await tester.pumpWidget(
      _host(
        width: 1280,
        touch: true,
        actions: _actions(
          retry: retried.add,
          exportConversation: () => exported.add('export'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final anchor = find.byKey(const ValueKey('genai-answer-menu-0'));
    final anchorRect = tester.getRect(anchor);
    await tester.tap(anchor);
    await tester.pumpAndSettle();

    expect(_anchoredMenu, findsOneWidget);
    final menuRect = tester.getRect(_anchoredMenu);
    expect(menuRect.overlaps(anchorRect), isFalse);
    expect(menuRect.top, closeTo(anchorRect.bottom + 7, 0.01));
    expect(find.text('重新生成'), findsOneWidget);
    expect(find.text('导出对话'), findsOneWidget);
    expect(_menuItemEnabled(tester, '重新生成'), isTrue);
    expect(_menuItemEnabled(tester, '导出对话'), isTrue);

    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();
    expect(retried, [0]);
    expect(exported, isEmpty);

    // Regenerate is unavailable without a campus connection, while export is not.
    await tester.pumpWidget(
      _host(width: 1280, touch: true, connected: false, actions: _actions()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('genai-answer-menu-0')));
    await tester.pumpAndSettle();
    expect(_menuItemEnabled(tester, '重新生成'), isFalse);
    expect(_menuItemEnabled(tester, '导出对话'), isTrue);
  });

  testWidgets('message menu opens clear of its button and preserves its rows', (tester) async {
    _sizeTo(tester, const Size(1280, 900));
    final copied = <(String, String)>[];
    final changed = <(int, String)>[];
    await tester.pumpWidget(
      _host(
        width: 1280,
        touch: true,
        count: 2,
        actions: _actions(
          copy: (text, message) => copied.add((text, message)),
          changeTurn: (index, action) => changed.add((index, action)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final anchor = _menu;
    final anchorRect = tester.getRect(anchor);
    await tester.tap(anchor);
    await tester.pumpAndSettle();

    expect(_anchoredMenu, findsOneWidget);
    final menuRect = tester.getRect(_anchoredMenu);
    expect(menuRect.overlaps(anchorRect), isFalse);
    expect(menuRect.top, closeTo(anchorRect.bottom + 7, 0.01));
    for (final label in ['复制内容', '编辑并重新发送', '回退到此处', '删除此轮及后续']) {
      expect(find.text(label), findsOneWidget);
      expect(_menuItemEnabled(tester, label), isTrue);
    }

    await tester.tap(find.text('复制内容'));
    await tester.pumpAndSettle();
    expect(copied, [('User prompt', '已复制内容')]);
    expect(changed, isEmpty);

    // A sending workspace disables the message menu from opening at all.
    await tester.pumpWidget(_host(width: 1280, touch: true, sending: true));
    await tester.pumpAndSettle();
    final disabled = tester.widget<IconButton>(_menu);
    expect(disabled.onPressed, isNull);
  });
}
