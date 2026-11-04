import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/presentation/genai_turn_edit_dialog.dart';
import 'package:techpie/features/genai/presentation/genai_turn_view.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

GenAiTurnActions _actions() => GenAiTurnActions(
      copy: (_, __) {},
      openLink: (_) {},
      changeTurn: (_, __) {},
      retry: (_) {},
      openImages: () {},
      showImage: ({Uint8List? bytes, String? url}) {},
      imageDisplayUri: (url) => Uri.parse(url),
      markdownImage: (uri, title, alt) => const SizedBox.shrink(),
      toggleTts: (_, __) {},
      approve: (_) {},
      reject: (_) {},
    );

GenAiTurnContext _context(double width) => GenAiTurnContext(
      index: 0,
      count: 1,
      sending: false,
      connected: true,
      touch: true,
      pendingApproval: null,
      latestVisual: null,
      supportsPlayback: false,
      playingTtsIndex: null,
      loadingTts: false,
      workspaceWidth: width,
    );

/// Records what Flutter's own copy/cut callbacks put on the clipboard.
List<String> _captureClipboard(WidgetTester tester) {
  final copies = <String>[];
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copies.add((call.arguments as Map)['text'] as String);
    }
    if (call.method == 'Clipboard.hasStrings') {
      return <String, dynamic>{'value': true};
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copies;
}

Finder get _popover => find.byType(AdaptiveTextSelectionToolbar);

/// Lands a long press on the first glyph of the answer paragraph rendered by
/// GenAiMarkdown, whose prose is a plain RichText inside the SelectionArea.
Offset _positionInsideAnswer(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byType(SelectionArea), matching: find.byType(RichText)).first,
  );
  final caret = paragraph.getOffsetForCaret(const TextPosition(offset: 1), Rect.zero);
  return paragraph.localToGlobal(Offset.zero) + caret + const Offset(0, 4);
}

void main() {
  testWidgets(
    'long pressing an assistant answer opens the platform selection menu',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 900);

      final copies = _captureClipboard(tester);

      final turn = GenAiConversationTurn('Ask something', id: 'turn-selection')
        ..answer = 'SelectableAnswer'
        ..phase = GenAiChatPhase.completed;

      await tester.pumpWidget(
        _host(
          LayoutBuilder(
            builder: (context, constraints) => GenAiTurnView(
              turn: turn,
              context: _context(constraints.maxWidth),
              actions: _actions(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);

      await tester.longPressAt(
        _positionInsideAnswer(tester),
      );
      await tester.pumpAndSettle();

      expect(_popover, findsOneWidget);

      // A read-only region offers copy/select-all through Flutter's own
      // callbacks, never cut.
      final copy = find.text('Copy');
      expect(copy, findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      expect(find.text('Cut'), findsNothing);

      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copies.join(), contains('SelectableAnswer'));
      // Restyling at the phone breakpoint replaces selection geometry, while
      // copying the same answer must remain available after the transition.
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.longPressAt(_positionInsideAnswer(tester));
      await tester.pumpAndSettle();
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copies, ['SelectableAnswer', 'SelectableAnswer']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the inline edit field exposes the platform menu with working copy and cut',
    (tester) async {
      final copies = _captureClipboard(tester);

      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GenAiTurnEditDialog(
              prompt: 'Edit me text',
              action: 'edit',
              removedTurns: 1,
              hasExternalActions: false,
              onSubmit: (value, commit) async {
                submitted = value;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fieldFinder = find.byType(TextField);
      expect(fieldFinder, findsOneWidget);
      final field = tester.widget<TextField>(fieldFinder);

      await tester.tap(fieldFinder);
      await tester.pump();
      final controller = field.controller!;
      controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
      await tester.pump();

      final editable = tester.state<EditableTextState>(
        find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
      );
      editable.toggleToolbar();
      await tester.pumpAndSettle();

      expect(_popover, findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      final cut = find.text('Cut');
      expect(cut, findsOneWidget);

      await tester.tap(cut);
      await tester.pumpAndSettle();

      // The row ran Flutter's cut callback: the text reached the clipboard and
      // left the controller, and nothing was submitted to the server.
      expect(copies.join(), contains('Edit me text'));
      expect(controller.text, isEmpty);
      expect(submitted, isNull);
      expect(_popover, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
