import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('renders Mermaid diagram from code block', (tester) async {
    const mermaidMarkdown = '''
```mermaid
graph TD
  A[开始] --> B{是否继续}
  B -->|是| C[处理中]
  B -->|否| D[结束]
```
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: mermaidMarkdown),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GenAiMermaidView), findsOneWidget);
    expect(find.byType(MermaidDiagram), findsOneWidget);
    expect(find.text('Mermaid 图表'), findsOneWidget);
    expect(find.text('流程图'), findsOneWidget);

    // Toggle to source code
    await tester.tap(find.byIcon(Icons.code_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('graph TD'), findsOneWidget);

    // Toggle back to diagram
    await tester.tap(find.byIcon(Icons.schema_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(MermaidDiagram), findsOneWidget);
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
    expect(find.text('流程图'), findsOneWidget);
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
    expect(find.text('状态图'), findsOneWidget);
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

  testWidgets('renders Markdown typography with headings, blockquotes, and tables', (tester) async {
    const typographyMarkdown = '''
# 一级标题
## 二级标题
### 三级标题

> 这是一段引用文本，测试样式。

这是一段正文，包含 `inline_code()` 行内代码。

| 模块 | 功能 | 状态 |
| :--- | :--- | :--- |
| STT | 语音识别 | 正常 |
| TTS | 语音合成 | 正常 |
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: typographyMarkdown),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('一级标题'), findsOneWidget);
    expect(find.text('二级标题'), findsOneWidget);
    expect(find.text('三级标题'), findsOneWidget);
    expect(find.textContaining('这是一段引用文本'), findsOneWidget);
    expect(find.textContaining('inline_code()'), findsOneWidget);
    expect(find.text('语音识别'), findsOneWidget);
    expect(find.text('语音合成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'theme-adaptive blockquotes eliminate light blue background in dark mode and use onSurfaceVariant text',
      (tester) async {
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
    );

    const quoteMarkdown = '> 黑暗模式下的引用块内容，具有高辨识度与舒适对比度。';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: quoteMarkdown),
        theme: darkTheme,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('黑暗模式下的引用块内容'), findsOneWidget);

    final selectableFinder = find.byType(SelectableText);
    expect(selectableFinder, findsWidgets);
    final selectable = tester.widgetList<SelectableText>(selectableFinder).firstWhere(
          (w) => w.textSpan?.toPlainText().contains('黑暗模式下的引用块内容') ?? false,
        );
    final resolvedStyle = selectable.textSpan?.style ??
        ((selectable.textSpan?.children?.isNotEmpty ?? false)
            ? (selectable.textSpan!.children!.first as TextSpan).style
            : null);
    expect(resolvedStyle?.color, darkTheme.colorScheme.onSurfaceVariant);

    final decoratedBoxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    final quoteBox = decoratedBoxes.firstWhere((w) {
      final dec = w.decoration;
      if (dec is BoxDecoration && dec.border is Border) {
        return (dec.border as Border).left.width == 3.5;
      }
      return false;
    });
    final boxDec = quoteBox.decoration as BoxDecoration;
    // Must NOT be the hardcoded flutter_markdown blue
    expect(boxDec.color, isNot(Colors.blue.shade100));
    expect(
      boxDec.color,
      darkTheme.colorScheme.surfaceContainerHighest.withValues(alpha: .28),
    );
  });

  testWidgets('handles edge-case markdown inputs gracefully without crashing', (tester) async {
    const edgeCases = '''
# 
>
> >
> > >

```
```

```unknown_lang_xyz
foo bar
```

---

***

| Col1 | Col2 |
| --- | --- |

[未闭合链接](
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: edgeCases),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
