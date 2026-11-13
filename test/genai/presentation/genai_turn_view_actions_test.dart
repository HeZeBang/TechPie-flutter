import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/presentation/genai_turn_view.dart';

const _turnId = 'turn-actions';

GenAiTurnActions _actions({
  void Function(String text, String message)? copy,
  void Function(int index, String action)? changeTurn,
  void Function(int index)? retry,
  Uri Function(String)? imageDisplayUri,
}) => GenAiTurnActions(
  copy: copy ?? (_, __) {},
  openLink: (_) {},
  changeTurn: changeTurn ?? (_, __) {},
  retry: retry ?? (_) {},
  openImages: () {},
  showImage: ({Uint8List? bytes, String? url}) {},
  imageDisplayUri: imageDisplayUri ?? (url) => Uri.parse(url),
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
}) => GenAiTurnContext(
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
  List<String> imageUrls = const [],
}) {
  final turn = GenAiConversationTurn('User prompt', id: _turnId)
    ..attachedImageUrls = imageUrls
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

void _sizeTo(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder get _bubble => find.byKey(const ValueKey('genai-user-bubble-$_turnId'));
Finder get _actionsRow => find.byKey(const ValueKey('genai-user-actions-$_turnId'));
Finder get _edit => find.byKey(const ValueKey('genai-turn-edit-$_turnId'));
Finder get _copy => find.byKey(const ValueKey('genai-turn-copy-$_turnId'));

void main() {
  testWidgets('unsafe restored image URLs leave the prompt and answer readable', (tester) async {
    await tester.pumpWidget(
      _host(
        width: 800,
        touch: false,
        imageUrls: ['http://127.0.0.1/private', 'https://other.example/image.png'],
        actions: _actions(imageDisplayUri: genAiImageUri),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('User prompt'), findsOneWidget);
    expect(find.text('Answer body'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  for (final width in [375.0, 1280.0]) {
    testWidgets('campus-network warning fits the viewport at $width', (tester) async {
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
      final retry = find.byKey(const ValueKey('genai-retry-0'));
      expect(retry.hitTestable(), findsOneWidget);
      expect(tester.getRect(title).right, lessThanOrEqualTo(width));
      expect(tester.getRect(retry).overlaps(tester.getRect(title)), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop hover reveals actions without moving the bubble or answer', (tester) async {
    _sizeTo(tester, const Size(1280, 900));
    await tester.pumpWidget(_host(width: 1280, touch: false));
    await tester.pumpAndSettle();

    // Hidden actions are not laid out at all.
    expect(_actionsRow, findsNothing);
    final hiddenHeight = tester.getSize(find.byType(GenAiTurnView)).height;
    final hiddenBubble = tester.getRect(_bubble);
    expect(hiddenBubble.right, tester.getRect(find.byType(GenAiTurnView)).right);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await tester.pump();
    await pointer.moveTo(tester.getCenter(_bubble));
    await tester.pumpAndSettle();

    expect(_actionsRow, findsOneWidget);
    expect(_edit.hitTestable(), findsOneWidget);
    expect(_copy.hitTestable(), findsOneWidget);
    expect(tester.getRect(_bubble), hiddenBubble);
    expect(tester.getSize(find.byType(GenAiTurnView)).height, hiddenHeight);
  });

  testWidgets('reply actions regenerate while export belongs to the conversation', (tester) async {
    final retried = <int>[];
    final actions = _actions(retry: retried.add);
    await tester.pumpWidget(_host(width: 375, touch: true, actions: actions));
    await tester.tap(find.byTooltip('重新生成'));
    expect(retried, [0]);
    await tester.pumpWidget(_host(width: 375, touch: true, connected: false, actions: actions));
    expect(find.byTooltip('重新生成'), findsNothing);
    expect(find.byTooltip('导出对话'), findsNothing);
  });

  testWidgets('long pressing prompt text opens its actions and respects sending state', (
    tester,
  ) async {
    _sizeTo(tester, const Size(390, 844));
    final copied = <(String, String)>[];
    final changed = <(int, String)>[];
    await tester.pumpWidget(
      _host(
        width: 390,
        touch: true,
        count: 2,
        actions: _actions(
          copy: (text, message) => copied.add((text, message)),
          changeTurn: (index, action) => changed.add((index, action)),
        ),
      ),
    );
    expect(_actionsRow, findsNothing);
    await tester.longPress(find.text('User prompt'));
    await tester.pumpAndSettle();
    final bubble = tester.getRect(_bubble);
    final menu = tester.getRect(find.byKey(const ValueKey('genai-anchored-menu')));
    expect(menu.overlaps(bubble), isFalse);
    expect(menu.right, lessThanOrEqualTo(390));
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
    await tester.longPress(find.text('User prompt'));
    await tester.pumpAndSettle();
    expect(find.text('编辑并重新发送'), findsNothing);
  });
}
