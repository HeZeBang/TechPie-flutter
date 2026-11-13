import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_markdown.dart';

Future<void> _showMarkdown(
  WidgetTester tester,
  String data, {
  bool compact = false,
  MarkdownStyleSheet? styleSheet,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: compact ? 375 : 640,
        child: GenAiMarkdown(data: data, compact: compact, styleSheet: styleSheet),
      ),
    ),
  ),
);

RenderParagraph _paragraph(WidgetTester tester, String prefix) => tester.renderObject(
  find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith(prefix)).first,
);

Rect _glyph(RenderParagraph paragraph, int offset) {
  final box = paragraph
      .getBoxesForSelection(TextSelection(baseOffset: offset, extentOffset: offset + 1))
      .first;
  return box.toRect().shift(paragraph.localToGlobal(Offset.zero));
}

void main() {
  testWidgets('custom heading and table styles preserve their emphasis', (tester) async {
    const color = Color(0xff123456);
    await _showMarkdown(
      tester,
      '# Heading\n\n| Header |\n| --- |\n| Value |',
      styleSheet: MarkdownStyleSheet(
        h1: const TextStyle(color: color),
        tableHead: const TextStyle(color: color),
      ),
    );

    TextStyle effectiveStyle(String text) {
      TextStyle? visit(InlineSpan span, TextStyle parent) {
        if (span is! TextSpan) return null;
        final style = parent.merge(span.style);
        if (span.text == text) return style;
        for (final child in span.children ?? const <InlineSpan>[]) {
          final match = visit(child, style);
          if (match != null) return match;
        }
        return null;
      }

      return visit(_paragraph(tester, text).text, const TextStyle())!;
    }

    for (final text in ['Heading', 'Header']) {
      final style = effectiveStyle(text);
      expect(style.color, color);
      expect(style.fontWeight!.value, greaterThan(FontWeight.normal.value));
    }
  });

  for (final compact in [true, false]) {
    testWidgets('wrapped list markers align with the first line (compact: $compact)', (
      tester,
    ) async {
      final words = List.filled(15, 'wrapped item').join(' ');
      await _showMarkdown(tester, '- Bullet $words\n\n1. Ordered $words', compact: compact);
      for (final (marker, prefix) in [('•', 'Bullet'), ('1.', 'Ordered')]) {
        final item = _paragraph(tester, prefix);
        final markerBounds = _glyph(_paragraph(tester, marker), 0);
        final first = _glyph(item, 0);
        final last = _glyph(item, item.text.toPlainText().length - 1);
        expect(last.top, greaterThan(first.top));
        expect(markerBounds.right, lessThan(first.left));
        expect(markerBounds.center.dy, closeTo(first.center.dy, 1.5));
      }
    });

    testWidgets('mixed CJK and Latin stay on separate authored lines (compact: $compact)', (
      tester,
    ) async {
      await _showMarkdown(
        tester,
        '第一行 mixed CJK 与 Latin  \n第二行 continues 混合 content',
        compact: compact,
      );
      final paragraph = _paragraph(tester, '第一行');
      final text = paragraph.text.toPlainText();
      expect(text.split('\n'), ['第一行 mixed CJK 与 Latin', '第二行 continues 混合 content']);
      final first = _glyph(paragraph, 0);
      final second = _glyph(paragraph, text.indexOf('第二行'));
      expect(second.top, greaterThanOrEqualTo(first.bottom - .5));
    });
  }
}
