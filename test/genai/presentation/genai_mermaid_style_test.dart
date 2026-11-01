import 'package:flutter/material.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_icons.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_mermaid_view.dart';

const _flow = '''
flowchart TD
  A[Input] -->|yes| B[Output]
''';

const _sequence = '''
sequenceDiagram
  participant A as Client
  participant B as Server
  A->>B: Request
  B-->>A: Response
''';

Widget _host(String code, ThemeData theme) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(child: GenAiMermaidView(code: code)),
      ),
    );

Future<MermaidPainter> _pumpAndReadPainter(
  WidgetTester tester,
  String code,
  Brightness brightness,
  bool Function(CustomPainter painter) matches,
) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.physicalSize = const Size(900, 900);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    _host(
      code,
      brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
    ),
  );
  await tester.pumpAndSettle();

  final finder = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter != null && matches(widget.painter!),
  );
  expect(finder, findsOneWidget);
  return tester.widget<CustomPaint>(finder).painter! as MermaidPainter;
}

GenAiPalette _paletteOf(WidgetTester tester) =>
    GenAiPalette.of(tester.element(find.byType(GenAiMermaidView)));

/// The draft's diagram grammar: a 1px line border on a soft 9px-radius node,
/// 13px regular-weight text, and 1–1.25px muted edges whose labels are 11–12px
/// on a raised chip. Colors are compared against [GenAiPalette] rather than
/// hard-coded values, so light, dark and dynamic-color themes all qualify.
void _expectDraftStyle(MermaidStyle style, GenAiPalette palette) {
  final node = style.defaultNodeStyle;
  final edge = style.defaultEdgeStyle;

  expect(style.backgroundColor, palette.raised.toARGB32());

  expect(node.strokeColor, palette.line.toARGB32());
  expect(node.strokeWidth, 1.0);
  expect(node.strokeWidth, lessThanOrEqualTo(1.25));
  expect(node.borderRadius, 9);
  expect(node.fillColor, palette.soft.toARGB32());
  expect(node.textColor, palette.text.toARGB32());
  expect(node.fontSize, 13);
  expect(node.fontWeight, FontWeight.w400);

  expect(edge.strokeColor, palette.muted.toARGB32());
  expect(edge.strokeWidth, greaterThanOrEqualTo(1.0));
  expect(edge.strokeWidth, lessThanOrEqualTo(1.25));
  expect(edge.labelColor, palette.muted.toARGB32());
  expect(edge.labelFontSize, inInclusiveRange(11.0, 12.0));
  expect(edge.labelBackgroundColor, palette.raised.toARGB32());
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('flowchart painter follows the palette (${brightness.name})', (tester) async {
      final style = (await _pumpAndReadPainter(
        tester,
        _flow,
        brightness,
        (painter) => painter is FlowchartPainter,
      ))
          .style;
      _expectDraftStyle(style, _paletteOf(tester));
    });

    testWidgets(
      'sequence painter inherits the same palette and thin dashed lifelines (${brightness.name})',
      (tester) async {
        final style = (await _pumpAndReadPainter(
          tester,
          _sequence,
          brightness,
          (painter) => painter is SequencePainter,
        ))
            .style;
        final palette = _paletteOf(tester);
        _expectDraftStyle(style, palette);
        // SequencePainter paints its dashed lifelines from the default edge
        // color, so the muted 1–1.25px treatment reaches them as well.
        expect(style.defaultEdgeStyle.strokeColor, palette.muted.toARGB32());
        expect(style.defaultEdgeStyle.strokeWidth, lessThanOrEqualTo(1.25));
      },
    );
  }

  testWidgets('sequence painter records the draft paint commands', (tester) async {
    final painter = await _pumpAndReadPainter(
      tester,
      _sequence,
      Brightness.light,
      (painter) => painter is SequencePainter,
    );
    final palette = _paletteOf(tester);

    final canvas = TestRecordingCanvas();
    painter.paint(canvas, const Size(600, 400));

    bool paints(Paint paint, Color color) =>
        paint.color.toARGB32() == color.toARGB32();

    List<Invocation> calls(Symbol name) => [
          for (final recorded in canvas.invocations)
            if (recorded.invocation.memberName == name) recorded.invocation,
        ];
    final rrects = calls(#drawRRect);
    final lines = calls(#drawLine);

    expect(
      rrects.any((call) {
        final paint = call.positionalArguments[1] as Paint;
        return paint.style == PaintingStyle.fill && paints(paint, palette.soft);
      }),
      isTrue,
      reason: 'participant fill uses the palette soft role',
    );
    expect(
      rrects.any((call) {
        final paint = call.positionalArguments[1] as Paint;
        return paint.style == PaintingStyle.stroke &&
            paints(paint, palette.line) &&
            paint.strokeWidth == 1;
      }),
      isTrue,
      reason: 'participant border is a 1px line stroke',
    );
    expect(
      rrects.any((call) => (call.positionalArguments[0] as RRect).tlRadiusX == 9),
      isTrue,
      reason: 'participant corners are 9px',
    );
    expect(
      lines.any((call) {
        final paint = call.positionalArguments[2] as Paint;
        return paints(paint, palette.muted) &&
            (paint.strokeWidth - 1.15).abs() < .001;
      }),
      isTrue,
      reason: 'dashed lifelines and messages use muted 1.15px strokes',
    );
    expect(
      rrects.any((call) {
        final paint = call.positionalArguments[1] as Paint;
        return paint.style == PaintingStyle.fill && paints(paint, palette.raised);
      }),
      isTrue,
      reason: 'edge labels paint a raised background chip',
    );
    expect(
      calls(#scale).any((call) => call.positionalArguments.first == .65),
      isTrue,
      reason: 'arrowheads are drawn at 65% size',
    );
    expect(calls(#drawPath), isNotEmpty, reason: 'arrowheads are paths');
  });

  testWidgets('header diagram glyph uses the palette accent, not the scheme primary',
      (tester) async {
    await tester.pumpWidget(_host(_flow, ThemeData.light()));
    await tester.pumpAndSettle();

    final icons = find.byWidgetPredicate(
      (widget) => widget is GenAiIcon && widget.glyph == GenAiGlyph.diagram,
    );
    expect(icons, findsOneWidget);

    final palette = _paletteOf(tester);
    expect(tester.widget<GenAiIcon>(icons).color, palette.accent);
  });
}
