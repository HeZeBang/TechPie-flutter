import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_markdown.dart';

void main() {
  testWidgets('visual headers use the fence title and fall back for old messages', (tester) async {
    for (final (metadata, title) in [
      (' {"title":"曲线与切线"}', '曲线与切线'),
      (' {"title":"  "}', '交互示例'),
      ('', '交互示例'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GenAiMarkdown(
              data: '```techpie-visual$metadata\n<title>HTML title</title><p>Example</p>\n',
              interactiveVisuals: true,
            ),
          ),
        ),
      );
      expect(find.text(title), findsOneWidget);
      expect(find.text('HTML title'), findsNothing);
      expect(find.text('正在生成交互示例…'), findsOneWidget);
      await tester.tap(find.text(title));
      await tester.pump();
      expect(find.text('正在生成交互示例…'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
