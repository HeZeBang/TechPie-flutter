import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_markdown.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';

void main() {
  Widget buildApp(Widget child, {ThemeData? theme}) {
    return MaterialApp(
      theme: theme,
      builder: (_, child) => AdaptiveFeedbackHost(
        key: adaptiveFeedbackHostKey,
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  testWidgets('streaming a new reply reuses the rendered widgets of older replies', (tester) async {
    final history = List.generate(
      12,
      (index) => 'Reply $index with **formatted text** and inline \$x^2\$.\n\n'
          '```dart\nfinal answer = $index;\n```\n\n'
          '- First item\n- Second item',
    );
    Widget conversation(String stream, {int latestVisual = 1}) => buildApp(
          Column(
            children: [
              for (var index = 0; index < history.length; index++)
                GenAiMarkdown(
                  key: ValueKey(index),
                  data: history[index],
                  latestVisual: ('streaming', latestVisual),
                ),
              GenAiMarkdown(data: stream),
            ],
          ),
        );
    await tester.pumpWidget(conversation('Starting'));
    final originalBlocks = tester
        .widgetList<GenAiStandardCodeBlock>(
          find.byType(GenAiStandardCodeBlock),
        )
        .toList();
    expect(originalBlocks, hasLength(history.length));

    for (var chunk = 1; chunk <= 6; chunk++) {
      await tester.pumpWidget(conversation('Streaming chunk $chunk', latestVisual: chunk));
      final currentBlocks = tester
          .widgetList<GenAiStandardCodeBlock>(
            find.byType(GenAiStandardCodeBlock),
          )
          .toList();
      for (var index = 0; index < originalBlocks.length; index++) {
        expect(
          identical(currentBlocks[index], originalBlocks[index]),
          isTrue,
          reason: 'Streaming must not rebuild the Markdown of completed reply $index.',
        );
      }
      expect(find.text('Streaming chunk $chunk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('cached Markdown uses the latest link callback without rebuilding content',
      (tester) async {
    final tapped = <String>[];
    Widget content(String callback) => buildApp(
          GenAiMarkdown(
            data: '[Open docs](https://example.com)\n\n```dart\nfinal value = 1;\n```',
            selectable: false,
            onTapLink: (_, href, __) => tapped.add('$callback:$href'),
          ),
        );
    await tester.pumpWidget(content('first'));
    final original = tester.widget<GenAiStandardCodeBlock>(find.byType(GenAiStandardCodeBlock));
    await tester.tap(find.text('Open docs', findRichText: true));
    await tester.pumpWidget(content('second'));
    await tester.tap(find.text('Open docs', findRichText: true));
    expect(tapped, ['first:https://example.com', 'second:https://example.com']);
    expect(
      identical(
        tester.widget<GenAiStandardCodeBlock>(find.byType(GenAiStandardCodeBlock)),
        original,
      ),
      isTrue,
    );
  });

  testWidgets('cached document refreshes typography and streamed reference definitions',
      (tester) async {
    final tapped = <String?>[];
    Widget content(String data, Color color) => buildApp(
          Builder(
            builder: (context) => GenAiMarkdown(
              data: data,
              selectable: false,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: TextStyle(color: color),
              ),
              onTapLink: (_, href, __) => tapped.add(href),
            ),
          ),
        );
    const data = 'Paragraph\n\n[Open docs][guide]';
    Color? paragraphColor() => tester
        .widget<RichText>(find.text('Paragraph', findRichText: true))
        .text
        .getSpanForPosition(const TextPosition(offset: 0))
        ?.style
        ?.color;
    await tester.pumpWidget(content(data, Colors.red));
    expect(paragraphColor(), Colors.red);
    await tester.pumpWidget(content(data, Colors.blue));
    expect(paragraphColor(), Colors.blue);
    await tester.pumpWidget(content('$data\n\n[guide]: https://example.com', Colors.blue));
    await tester.tap(find.text('Open docs', findRichText: true));
    expect(tapped, ['https://example.com']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged Markdown refreshes visual mode and attachment rendering', (tester) async {
    const data = '![attachment](https://example.com/image.png)\n\n'
        '```techpie-visual\n<p>Still streaming';
    Widget content(bool visual, String label) => buildApp(
          GenAiMarkdown(
            data: data,
            interactiveVisuals: visual,
            imageBuilder: (_, __, ___) => Text(label),
          ),
        );
    await tester.pumpWidget(content(false, 'first renderer'));
    expect(find.text('first renderer'), findsOneWidget);
    expect(find.text('正在生成交互示例…'), findsNothing);
    await tester.pumpWidget(content(true, 'replacement renderer'));
    expect(find.text('first renderer'), findsNothing);
    expect(find.text('replacement renderer'), findsOneWidget);
    expect(find.text('正在生成交互示例…'), findsOneWidget);
    await tester.pumpWidget(content(false, 'replacement renderer'));
    expect(find.text('正在生成交互示例…'), findsNothing);
  });

  testWidgets('empty streamed task items render and tear down safely', (tester) async {
    for (final input in ['- [x] ', '- [ ] ', '> - [x] ', '1. [x] ']) {
      for (var length = 1; length <= input.length; length++) {
        await tester.pumpWidget(
          buildApp(GenAiMarkdown(data: input.substring(0, length))),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('genai-markdown-fallback')),
          findsNothing,
        );
      }
      await tester.pumpWidget(buildApp(GenAiMarkdown(data: '${input}finished')));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    }
  });

  test('semicolon Mermaid statements parse without splitting labels or comments', () {
    const parser = MermaidParser();
    final normalized = normalizeMermaid('graph LR; A[Start] --> B[Done]; B --> C[End]');
    expect(parser.parse(normalized), isNotNull);
    expect(normalized, contains('graph LR\n'));
    expect(
      normalizeMermaid('graph LR; A[First; second] --> B[Done]'),
      contains('First; second'),
    );
    expect(
      normalizeMermaid('graph LR; A["Quoted; label"] --> B[Done]'),
      contains('Quoted; label'),
    );
    expect(
      normalizeMermaid('graph LR\n%% ignored; Z --> Y\nA --> B'),
      isNot(contains('Z')),
    );
    expect(
      normalizeMermaid('graph LR; A -->|Yes; proceed| B'),
      contains('Yes; proceed'),
    );
  });

  testWidgets('renders inline and block LaTeX equations in KaTeX-HTML style', (tester) async {
    const markdown = '''
由第 1 行只能取第 \$n\$ 列，第 2 行只能取第 \$n - 1\$ 列，依此类推。因此

\$\$\\boxed{D = (-1)^{\\frac{n(n-1)}{2}} a_{1n}a_{2,n-1}\\cdots a_{n1}}.\$\$

And code block math:
```latex
f(x) = \\sum_{i=1}^n x_i
```
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: markdown),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Math widgets are rendered (2 inline + 2 display math)
    expect(find.byType(Math), findsAtLeastNWidgets(3));
    expect(find.byType(GenAiLatexBlockView), findsNWidgets(2));
    // Verify no copy button on LaTeX display block (clean textbook style)
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });

  testWidgets('renders interactive BarChart, LineChart, and PieChart from code blocks',
      (tester) async {
    const barChartMarkdown = '''
```chart
{
  "type": "bar",
  "title": "月度销售",
  "labels": ["一月", "二月", "三月"],
  "datasets": [
    {
      "label": "2024",
      "data": [100, 200, 150]
    }
  ]
}
```
''';

    const lineChartMarkdown = '''
```chart
{
  "type": "line",
  "title": "温度趋势",
  "labels": ["08:00", "12:00", "16:00"],
  "datasets": [
    {
      "label": "气温",
      "data": [18.5, 26.0, 22.3]
    }
  ]
}
```
''';

    const pieChartMarkdown = '''
```chart:pie
{
  "title": "语言占比",
  "data": [
    {"name": "Dart", "value": 50},
    {"name": "Python", "value": 30},
    {"name": "Go", "value": 20}
  ]
}
```
''';

    // 1. BarChart
    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: barChartMarkdown),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('月度销售'), findsOneWidget);
    expect(find.text('柱状图'), findsOneWidget);

    // Toggle to code
    await tester.tap(find.byIcon(Icons.code_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('"type": "bar"'), findsOneWidget);

    // Toggle back to chart
    await tester.tap(find.byIcon(Icons.bar_chart_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(BarChart), findsOneWidget);

    // 2. LineChart
    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: lineChartMarkdown),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('温度趋势'), findsOneWidget);
    expect(find.text('折线图'), findsOneWidget);

    // 3. PieChart
    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: pieChartMarkdown),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.text('语言占比'), findsOneWidget);
    expect(find.text('饼图'), findsOneWidget);
  });

  testWidgets('invalid chart data shows source without crashing or inventing zeros',
      (tester) async {
    for (final code in [
      '{ invalid json syntax',
      '{"type":"line","values":["Infinity"]}',
      '{"type":"line","values":["NaN"]}',
      '{"type":"bar","values":["not a number"]}',
      '{"type":"bar","values":[1.7e308]}',
      '{"type":"line","values":[1e100]}',
      '{"type":"line","values":[5e-324]}',
      '{"type":"line","values":[-1e308,1e308]}',
      '{"type":"pie","values":[1e308,1e308]}',
      '{"type":"pie","values":[-1,2]}',
    ]) {
      await tester.pumpWidget(buildApp(GenAiMarkdown(data: '```chart\n$code\n```')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('格式未识别'), findsOneWidget);
      expect(find.text(code), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      expect(find.byType(BarChart), findsNothing);
      expect(find.byType(PieChart), findsNothing);
    }
  });

  testWidgets('renders AI-generated Mermaid with Chinese IDs, hyphens, and arrow labels',
      (tester) async {
    const aiMermaid = '''
```mermaid
graph TD
  开始[开始任务] -- 是 --> 校验-1{格式校验};
  校验-1 -->|成功| 结束[完成];
  校验-1 -->|失败| 失败节点;
```
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: aiMermaid),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GenAiMermaidView), findsOneWidget);
    expect(find.byType(MermaidDiagram), findsOneWidget);
    expect(find.text('Mermaid 图表'), findsOneWidget);
  });

  testWidgets('renders stateDiagram and classDiagram by normalizing to flowchart', (tester) async {
    const stateMermaid = '''
```mermaid
stateDiagram-v2
  [*] --> Still
  Still --> Moving : move
  Moving --> [*]
```
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: stateMermaid),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GenAiMermaidView), findsOneWidget);
    expect(find.byType(MermaidDiagram), findsOneWidget);
  });

  testWidgets('clipboard confirms success only after completion and reports denial',
      (tester) async {
    const dartMarkdown = '''
```dart
void main() {
  print("Hello, TechPie!");
}
```
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: dartMarkdown),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GenAiStandardCodeBlock), findsOneWidget);
    expect(find.text('DART'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.textContaining('print("Hello, TechPie!");'), findsOneWidget);

    var write = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') await write.future;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.tap(find.text('复制'));
    await tester.pump();
    expect(find.text('已复制'), findsNothing);
    write.completeError(PlatformException(code: 'denied'));
    await tester.pumpAndSettle();
    expect(find.text('已复制'), findsNothing);
    expect(find.text('无法复制，请手动选择文字'), findsOneWidget);
    expect(find.textContaining('print("Hello, TechPie!");'), findsOneWidget);

    write = Completer<void>();
    await tester.tap(find.text('复制'));
    await tester.pump();
    write.complete();
    await tester.pumpAndSettle();
    expect(find.text('已复制'), findsOneWidget);
    // Leaving a rendered answer cancels its delayed feedback reset.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  test('syntax highlighting preserves text and distinguishes lexical contexts', () {
    const highlighter = GenAiSyntaxHighlighter(brightness: Brightness.dark);
    final theme = SyntaxTheme.dark;
    const python = 'def add(x):\n    # return is a comment\n    return "def" + str(x)';
    final spans = highlighter.highlight(code: python, language: 'python');
    expect(spans.map((span) => span.text).join(), python);
    expect(
      spans.any(
        (span) => span.text == 'def' && span.style?.color == theme.keyword,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) => span.text == '# return is a comment' && span.style?.color == theme.comment,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) => span.text == '"def"' && span.style?.color == theme.string,
      ),
      isTrue,
    );
    const json = '{"name": "name", "count": 100}';
    final jsonSpans = highlighter.highlight(code: json, language: 'json');
    expect(jsonSpans.map((span) => span.text).join(), json);
    expect(
      jsonSpans.where((span) => span.text == '"name"').map((span) => span.style?.color),
      [theme.property, theme.string],
    );
  });
}
