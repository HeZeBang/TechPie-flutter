import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_markdown.dart';

Widget _host(Widget child, {required double width}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

/// Effective style of every span in the tree, walking ancestors so a leaf is
/// judged by the style it actually inherits rather than by its local style
/// alone (flutter_markdown nests the block style above the inline run).
Map<TextSpan, TextStyle> _effectiveSpans(WidgetTester tester) {
  final result = <TextSpan, TextStyle>{};
  void visit(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) {
      return;
    }
    final effective = inherited.merge(span.style);
    result[span] = effective;
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, effective);
    }
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(rich.text, const TextStyle());
  }
  return result;
}

TextStyle _effectiveStyle(WidgetTester tester, String text) {
  final match = _effectiveSpans(tester)
      .entries
      .where((entry) => entry.key.text == text)
      .map((entry) => entry.value);
  if (match.isEmpty) {
    throw StateError('No span carrying the text "$text"');
  }
  return match.first;
}

FontWeight _normalizedWeight(TextStyle style) => style.fontWeight ?? FontWeight.w400;

Finder _paragraphContaining(String text) => find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText().startsWith(text),
    );

Finder _richTextWithPlainText(String text) => find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
    );

/// Vertical centre of the first visual line, in the paragraph's local paint
/// coordinates. Boxes are grouped by line and the first line's boxes unioned.
double _firstLineCenterY(
  RenderParagraph paragraph,
  ui.BoxHeightStyle heightStyle,
) {
  final text = paragraph.text.toPlainText();
  final boxes = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
        boxHeightStyle: heightStyle,
      )
      .where((box) => box.toRect().height > 0)
      .toList();
  expect(boxes, isNotEmpty);
  final firstTop = boxes.map((box) => box.top).reduce(math.min);
  final firstLine = boxes.where((box) => (box.top - firstTop).abs() <= 1);
  final firstBottom = firstLine.map((box) => box.bottom).reduce(math.max);
  return (firstTop + firstBottom) / 2;
}

double _lineCenterY(
  RenderParagraph paragraph,
  ui.BoxHeightStyle heightStyle,
) {
  final box = paragraph
      .getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 1),
        boxHeightStyle: heightStyle,
      )
      .single
      .toRect();
  return box.center.dy;
}

/// Number of distinct visual lines the paragraph paints, counted from the
/// boxes Flutter reports for the whole run.
int _visualLineCount(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
    boxHeightStyle: ui.BoxHeightStyle.tight,
  );
  final tops = <double>[];
  for (final box in boxes.where((box) => box.toRect().height > 0)) {
    if (!tops.any((top) => (top - box.top).abs() <= 1)) {
      tops.add(box.top);
    }
  }
  return tops.length;
}

const _weightDocument = '# Heading One\n'
    '\n'
    '## Heading Two\n'
    '\n'
    '### Heading Three\n'
    '\n'
    'Body paragraph text with **Bold words**.\n'
    '\n'
    '| Name | Score |\n'
    '| --- | --- |\n'
    '| Ada | 10 |\n';

const _partialDocument = '# Partial One\n'
    '\n'
    '## Partial Two\n'
    '\n'
    '### Partial Three\n'
    '\n'
    '| Header | Value |\n'
    '| --- | --- |\n'
    '| Cell | 7 |\n';

const _listDocument = '- Bullet item that is long enough to wrap onto a second '
    'visual line for alignment checks\n'
    '- Short bullet\n'
    '\n'
    '1. Ordered item that is long enough to wrap onto a second visual line '
    'for alignment checks\n'
    '2. Short ordered\n';

const _mixedHardBreak = '第一行 mixed CJK 与 Latin  \n第二行 continues 混合 content';

void main() {
  for (final compact in <bool>[true, false]) {
    final width = compact ? 375.0 : 640.0;
    final fontSize = compact ? 14.0 : 15.0;

    testWidgets(
      'effective heading, strong and table-header weights are w600/w700 '
      '(compact: $compact)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _host(
            GenAiMarkdown(
              data: _weightDocument,
              compact: compact,
              selectable: true,
            ),
            width: width,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SelectionArea), findsOneWidget);

        expect(
          _effectiveStyle(tester, 'Heading One').fontWeight,
          FontWeight.w600,
        );
        expect(
          _effectiveStyle(tester, 'Heading Two').fontWeight,
          FontWeight.w600,
        );
        expect(
          _effectiveStyle(tester, 'Heading Three').fontWeight,
          FontWeight.w600,
        );
        expect(
          _effectiveStyle(tester, 'Bold words').fontWeight,
          FontWeight.w700,
        );

        // Sanity: the compact / desktop scale still reaches h2.
        expect(
          _effectiveStyle(tester, 'Heading Two').fontSize,
          compact ? 20 : 21,
        );
        // Body copy keeps the reading scale and leading.
        final body = _effectiveStyle(
          tester,
          'Body paragraph text with ',
        );
        expect(body.fontSize, fontSize);
        expect(body.height, 1.6);
        expect(body.leadingDistribution, TextLeadingDistribution.even);

        // The header row is a weight stronger than its cells even though the
        // header and body share the 12 px cell scale.
        expect(_effectiveStyle(tester, 'Name').fontWeight, FontWeight.w700);
        expect(_effectiveStyle(tester, 'Score').fontWeight, FontWeight.w700);
      },
    );

    testWidgets(
      'a partial stylesheet without fontWeight keeps the required weights '
      '(compact: $compact)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        const headingColor = Color(0xFF123456);
        const tableColor = Color(0xFF654321);
        final partial = MarkdownStyleSheet(
          h1: const TextStyle(fontSize: 30, color: headingColor),
          h2: const TextStyle(fontSize: 27, color: headingColor),
          h3: const TextStyle(fontSize: 24, color: headingColor),
          tableHead: const TextStyle(fontSize: 13, color: tableColor),
        );

        await tester.pumpWidget(
          _host(
            GenAiMarkdown(
              data: _partialDocument,
              compact: compact,
              selectable: true,
              styleSheet: partial,
            ),
            width: width,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (final (text, size) in <(String, double)>[
          ('Partial One', 30),
          ('Partial Two', 27),
          ('Partial Three', 24),
        ]) {
          final style = _effectiveStyle(tester, text);
          expect(style.fontSize, size, reason: 'partial size for $text');
          expect(style.color, headingColor, reason: 'partial color for $text');
          expect(
            style.fontWeight,
            FontWeight.w600,
            reason: 'partial h must still be w600 for $text',
          );
        }

        final header = _effectiveStyle(tester, 'Header');
        expect(header.fontSize, 13);
        expect(header.color, tableColor);
        expect(
          header.fontWeight,
          FontWeight.w700,
          reason: 'a partial tableHead must still be w700',
        );
        final value = _effectiveStyle(tester, 'Value');
        expect(value.fontWeight, FontWeight.w700);
      },
    );

    testWidgets(
      'list markers are plain body-weight bullets aligned with the first item '
      'line (compact: $compact)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _host(
            GenAiMarkdown(
              data: _listDocument,
              compact: compact,
              selectable: true,
            ),
            width: width,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final bodyColor = _effectiveStyle(tester, 'Short bullet').color;
        final accent = Theme.of(tester.element(find.byType(GenAiMarkdown))).colorScheme.primary;
        expect(
          bodyColor,
          isNot(accent),
          reason: 'list copy stays body-coloured, not accent',
        );

        // Dots are slightly larger; both marker styles retain the same line
        // height, normal weight, and body colour.
        for (final marker in <String>['•', '1.']) {
          final style = _effectiveStyle(tester, marker);
          expect(style.fontSize! * style.height!, closeTo(fontSize * 1.6, .01));
          expect(
            _normalizedWeight(style),
            FontWeight.w400,
            reason: 'marker $marker must be plain normal weight',
          );
          expect(
            style.color,
            bodyColor,
            reason: 'marker $marker shares the paragraph colour',
          );
          expect(
            style.color,
            isNot(accent),
            reason: 'marker $marker is not accent-coloured',
          );
        }

        for (final (markerText, itemText) in <(String, String)>[
          ('•', 'Bullet item that is long enough'),
          ('1.', 'Ordered item that is long enough'),
        ]) {
          final markerFinder = _richTextWithPlainText(markerText).first;
          final itemFinder = _paragraphContaining(itemText);
          expect(markerFinder, findsOneWidget);
          expect(itemFinder, findsOneWidget);

          // A dedicated gutter separates the marker from the text, including
          // bold first words and wrapped continuation lines.
          final indent = tester.getTopLeft(itemFinder).dx - tester.getTopLeft(markerFinder).dx;
          expect(indent, 34);
          final markerParagraphForGap = tester.renderObject<RenderParagraph>(markerFinder);
          final boxes = markerParagraphForGap.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: markerText.length),
          );
          final glyphEnd = tester.getTopLeft(markerFinder).dx + boxes.last.right;
          expect(tester.getTopLeft(itemFinder).dx - glyphEnd, greaterThanOrEqualTo(9));

          final markerParagraph = tester.renderObject<RenderParagraph>(markerFinder);
          final itemParagraph = tester.renderObject<RenderParagraph>(itemFinder);

          // The item must wrap, so this compares the marker against the first
          // of several visual lines rather than against a one-line shortcut.
          expect(
            _visualLineCount(itemParagraph),
            greaterThanOrEqualTo(2),
            reason: 'item $itemText must wrap',
          );

          for (final heightStyle in <ui.BoxHeightStyle>[
            ui.BoxHeightStyle.tight,
            ui.BoxHeightStyle.max,
          ]) {
            final markerCenter =
                tester.getTopLeft(markerFinder).dy + _lineCenterY(markerParagraph, heightStyle);
            final itemCenter =
                tester.getTopLeft(itemFinder).dy + _firstLineCenterY(itemParagraph, heightStyle);
            expect(
              (markerCenter - itemCenter).abs(),
              lessThanOrEqualTo(1.5),
              reason: 'marker $markerText [$heightStyle] must share the first '
                  'line centre within 1.5 px',
            );
          }
        }
      },
    );

    testWidgets(
      'a mixed CJK/Latin paragraph keeps hard-break lines apart and even '
      'leading (compact: $compact)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _host(
            GenAiMarkdown(
              data: _mixedHardBreak,
              compact: compact,
              selectable: true,
            ),
            width: width,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SelectionArea), findsOneWidget);

        final finder = find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('第一行') &&
              widget.text.toPlainText().contains('第二行'),
        );
        expect(
          finder,
          findsOneWidget,
          reason: 'the hard break must stay inside one paragraph',
        );
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final text = paragraph.text.toPlainText();
        expect(
          text.split('\n').length,
          2,
          reason: 'exactly the two authored lines, no extra blank paragraph',
        );

        final style = _effectiveStyle(tester, '第一行 mixed CJK 与 Latin');
        expect(style.fontSize, fontSize);
        expect(style.height, 1.6);
        expect(
          style.leadingDistribution,
          TextLeadingDistribution.even,
          reason: 'the paragraph leading is distributed evenly',
        );

        for (final heightStyle in <ui.BoxHeightStyle>[
          ui.BoxHeightStyle.tight,
          ui.BoxHeightStyle.max,
        ]) {
          final boxes = paragraph
              .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: text.length),
                boxHeightStyle: heightStyle,
              )
              .map((box) => box.toRect())
              .where((rect) => rect.height > 0)
              .toList();
          expect(boxes, isNotEmpty);

          final lineTops = <double>[];
          for (final rect in boxes) {
            if (!lineTops.any((top) => (top - rect.top).abs() <= 1)) {
              lineTops.add(rect.top);
            }
          }
          lineTops.sort();
          expect(
            lineTops.length,
            2,
            reason: '[${heightStyle.name}] the hard break yields two lines',
          );

          final lineRects = <Rect>[];
          for (final top in lineTops) {
            final line = boxes.where((rect) => (rect.top - top).abs() <= 1);
            lineRects.add(
              Rect.fromLTRB(
                line.map((rect) => rect.left).reduce(math.min),
                line.map((rect) => rect.top).reduce(math.min),
                line.map((rect) => rect.right).reduce(math.max),
                line.map((rect) => rect.bottom).reduce(math.max),
              ),
            );
          }
          for (var index = 1; index < lineRects.length; index++) {
            // BoxHeightStyle.max reports whole line boxes whose edges can
            // round into each other by a fraction of a logical pixel; the
            // lines still never substantially overlap.
            final tolerance = heightStyle == ui.BoxHeightStyle.max ? 0.5 : 0.01;
            expect(
              lineRects[index].top,
              greaterThanOrEqualTo(lineRects[index - 1].bottom - tolerance),
              reason: '[${heightStyle.name}] line $index must not overlap '
                  'line ${index - 1}',
            );
          }
        }
      },
    );
  }
}
