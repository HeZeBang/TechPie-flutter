import 'package:flutter/material.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_mermaid_view.dart';

void main() {
  for (final source in ['flowchart TD\n A --> B', 'sequenceDiagram\n A->>B: Request']) {
    testWidgets('${source.split('\n').first} canvas and labels follow app theme changes', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(child: GenAiMermaidView(code: source)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final canvas = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is MermaidPainter,
        );
        final painter = tester.widget<CustomPaint>(canvas).painter! as MermaidPainter;
        final palette = GenAiPalette.of(tester.element(canvas));
        expect(painter.style.backgroundColor, palette.raised.toARGB32());
        expect(painter.style.defaultNodeStyle.textColor, palette.text.toARGB32());
        expect(painter.style.defaultNodeStyle.fillColor, isNot(painter.style.backgroundColor));
      }
    });
  }
}
