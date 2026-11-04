import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/presentation/genai_icons.dart';
import 'package:techpie/features/genai/presentation/genai_turn_view.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_code_font.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_markdown.dart';

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
      touch: false,
      pendingApproval: null,
      latestVisual: null,
      supportsPlayback: false,
      playingTtsIndex: null,
      loadingTts: false,
      workspaceWidth: width,
    );

/// Walks every RichText span, because GenAiMarkdown owns selection with a
/// SelectionArea and renders its prose as non-selectable `Text.rich`.
/// Only RichText is walked: a SelectableText.code block would otherwise be
/// visited through both its widget and the RichText it builds.
Iterable<TextSpan> _allSpans(WidgetTester tester) sync* {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    final span = rich.text;
    if (span is! TextSpan) continue;
    yield* _flatten(span);
  }
}

Iterable<TextSpan> _flatten(TextSpan span) sync* {
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) yield* _flatten(child);
  }
}

TextSpan _spanWith(WidgetTester tester, String text) {
  final match = _allSpans(tester).firstWhere(
    (span) => span.text == text,
    orElse: () => throw StateError('No span with text "$text"'),
  );
  return match;
}

const _richAnswer = r'''
# Heading One

## Heading Two

### Heading Three

Body paragraph text.

**Bold words** and *italic words*.

`inline_code()` and [TechPie Link](https://example.com/docs).

1. Ordered item
2. Another ordered

- Bullet item
- Another bullet

| Name | Score |
| --- | --- |
| Ada | 10 |

```dart
final value = 42;
```

Inline math $x^2 + y^2$ and display math:

$$
\int_0^1 x^2 \, dx = \frac{1}{3}
$$

```mermaid
graph TD
  A[Start] --> B[Done]
```
''';

void main() {
  testWidgets('wide tables scroll without squeezing cells or overflowing the chat', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenAiMarkdown(
            data:
                '| Name | Description | Result | Status |\n| --- | --- | --- | --- |\n| GenAiStandardCodeBlock | **Readable** details | 42 | Done |',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    final table = tester.widget<Table>(find.byType(Table));
    expect(table.defaultColumnWidth, isA<IntrinsicColumnWidth>());
    await tester.drag(scroll, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rich answer renders headings, emphasis, lists, table, code, math and mermaid at each width',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      final turn = GenAiConversationTurn('Show me everything', id: 'turn-rich')
        ..answer = _richAnswer
        ..phase = GenAiChatPhase.completed;

      for (final width in <double>[375, 1280]) {
        tester.view.physicalSize = Size(width, 2600);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _host(
            GenAiTurnView(
              key: ValueKey<double>(width),
              turn: turn,
              context: _context(width),
              actions: _actions(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'width $width must not throw');
        expect(
          find.byKey(const ValueKey('genai-markdown-fallback')),
          findsNothing,
          reason: 'width $width must render through the real Markdown builder',
        );

        // Every block type the answer asks for survives the trip through
        // GenAiTurnView.
        expect(find.byType(GenAiStandardCodeBlock), findsOneWidget);
        expect(find.byType(GenAiMermaidView), findsOneWidget);
        expect(find.byType(Math), findsAtLeastNWidgets(2));
        final primary = Theme.of(tester.element(find.byType(GenAiTurnView))).colorScheme.primary;

        final h1 = _spanWith(tester, 'Heading One');
        final h2 = _spanWith(tester, 'Heading Two');
        final h3 = _spanWith(tester, 'Heading Three');
        expect(h1.style?.fontSize, 22);
        expect(h3.style?.fontSize, 17);

        // Body copy and h2 follow the compact (375) or desktop (1280) scale.
        final compact = width < 960;
        final body = _spanWith(tester, 'Body paragraph text.');
        expect(body.style?.fontSize, compact ? 14 : 15);
        expect(body.style?.height, 1.6);
        expect(h2.style?.fontSize, compact ? 20 : 21);
        expect(h2.style?.height, 1.4);

        final bold = _spanWith(tester, 'Bold words');
        expect(bold.style?.fontWeight, FontWeight.bold);
        final italic = _spanWith(tester, 'italic words');
        expect(italic.style?.fontStyle, FontStyle.italic);

        final code = _spanWith(tester, 'inline_code()');
        expect(code.style?.fontFamily, kGenAiMonospaceFamily);
        expect(code.style?.backgroundColor, isNotNull);

        final link = _spanWith(tester, 'TechPie Link');
        expect(link.style?.color, primary);
        expect(link.style?.decoration, TextDecoration.underline);

        // Lists render their items; the ordered / unordered bullets differ.
        expect(_spanWith(tester, 'Ordered item').style?.fontSize, compact ? 14 : 15);
        expect(_spanWith(tester, 'Another ordered').text, 'Another ordered');
        expect(_spanWith(tester, 'Bullet item').text, 'Bullet item');
        expect(_spanWith(tester, 'Another bullet').text, 'Another bullet');

        // Table cells carry the tableBody style, not the paragraph style.
        final cell = _spanWith(tester, 'Ada');
        expect(cell.style?.fontSize, compact ? 13 : 14);
        expect(cell.style?.height, 1.6);
      }
    },
  );

  testWidgets(
    'mixed CJK and ASCII code keeps gutter and content baselines aligned',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;

      const code = '第一行 alpha = 1;\n'
          'second line 内容 = "混合 CJK 与 ASCII";\n'
          '第三行 done();';

      await tester.pumpWidget(_host(const GenAiStandardCodeBlock(code: code)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // An unlabelled fence names its language "代码" rather than "CODE", and
      // the copy action is glyph-only.
      expect(find.text('代码'), findsOneWidget);
      expect(find.text('CODE'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is GenAiIcon && widget.glyph == GenAiGlyph.copy,
        ),
        findsOneWidget,
      );

      final gutterFinder = find.byKey(const ValueKey('genai-code-gutter'));
      final contentFinder = find.byKey(const ValueKey('genai-code-content'));
      expect(gutterFinder, findsOneWidget);
      expect(contentFinder, findsOneWidget);

      final gutter = tester.widget<Text>(gutterFinder);
      final content = tester.widget<SelectableText>(contentFinder);

      // Gutter and code share the forced strut and text-height policy.
      expect(gutter.strutStyle?.forceStrutHeight, isTrue);
      expect(content.strutStyle?.forceStrutHeight, isTrue);
      expect(gutter.strutStyle?.height, content.strutStyle?.height);
      expect(gutter.strutStyle?.fontSize, content.strutStyle?.fontSize);
      expect(gutter.strutStyle?.fontFamily, content.strutStyle?.fontFamily);
      expect(gutter.textHeightBehavior, content.textHeightBehavior);

      final gutterPainter = TextPainter(
        text: TextSpan(text: gutter.data, style: gutter.style),
        textDirection: TextDirection.ltr,
        strutStyle: gutter.strutStyle,
        textAlign: gutter.textAlign ?? TextAlign.right,
        textHeightBehavior: gutter.textHeightBehavior,
        textScaler: gutter.textScaler ?? TextScaler.noScaling,
      )..layout();
      final contentPainter = TextPainter(
        text: content.textSpan,
        textDirection: content.textDirection ?? TextDirection.ltr,
        strutStyle: content.strutStyle,
        textAlign: content.textAlign ?? TextAlign.start,
        textHeightBehavior: content.textHeightBehavior,
        textScaler: content.textScaler ?? TextScaler.noScaling,
      )..layout();
      addTearDown(gutterPainter.dispose);
      addTearDown(contentPainter.dispose);

      final gutterLines = gutterPainter.computeLineMetrics();
      final contentLines = contentPainter.computeLineMetrics();
      expect(gutterLines.length, 3);
      expect(contentLines.length, 3);

      final gutterOrigin = tester.getTopLeft(gutterFinder);
      final contentOrigin = tester.getTopLeft(contentFinder);
      for (var line = 0; line < 3; line++) {
        final gutterBaseline = gutterOrigin.dy + gutterLines[line].baseline;
        final contentBaseline = contentOrigin.dy + contentLines[line].baseline;
        expect(
          (gutterBaseline - contentBaseline).abs(),
          lessThanOrEqualTo(1),
          reason: 'line $line baseline must match the gutter within 1px',
        );
      }
    },
  );
}
