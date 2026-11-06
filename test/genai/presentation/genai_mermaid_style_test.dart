import 'package:flutter/material.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
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

// Verify theme propagation into each renderer, without duplicating style constants.
void _expectPalette(MermaidStyle style, GenAiPalette palette) {
  expect(style.backgroundColor, palette.raised.toARGB32());
  expect(style.defaultNodeStyle.fillColor, isNot(style.backgroundColor));
  expect(style.defaultNodeStyle.textColor, palette.text.toARGB32());
  expect(style.defaultEdgeStyle.strokeColor, palette.muted.toARGB32());
  expect(style.defaultEdgeStyle.labelColor, palette.muted.toARGB32());
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
      _expectPalette(style, _paletteOf(tester));
    });

    testWidgets(
      'sequence painter follows the palette (${brightness.name})',
      (tester) async {
        final style = (await _pumpAndReadPainter(
          tester,
          _sequence,
          brightness,
          (painter) => painter is SequencePainter,
        ))
            .style;
        final palette = _paletteOf(tester);
        _expectPalette(style, palette);
      },
    );
  }
}
