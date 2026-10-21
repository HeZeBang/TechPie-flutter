import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_markdown.dart';

void main() {
  Widget buildApp(Widget child, {ThemeData? theme}) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  testWidgets('renders inline and block LaTeX equations in KaTeX-HTML style',
      (tester) async {
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

  testWidgets(
      'renders interactive BarChart, LineChart, and PieChart from code blocks',
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

  testWidgets(
      'handles malformed chart JSON gracefully with error badge and code view',
      (tester) async {
    const invalidChartMarkdown = '''
```chart
{ invalid json syntax
```
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: invalidChartMarkdown),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('格式未识别'), findsOneWidget);
    expect(find.text('{ invalid json syntax'), findsOneWidget);
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

  testWidgets(
      'renders AI-generated Mermaid with Chinese IDs, hyphens, and arrow labels',
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

  testWidgets(
      'renders stateDiagram and classDiagram by normalizing to flowchart',
      (tester) async {
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

  testWidgets('renders standard code block with language chip and copy button',
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

    // Tap copy
    await tester.tap(find.text('复制'));
    await tester.pump();
    await tester.pump();
    expect(find.text('已复制'), findsOneWidget);
  });

  testWidgets('renders multi-line code block with line numbers gutter',
      (tester) async {
    const multiLineCode = '''
```python
def add(a, b):
    # Calculate sum
    return a + b
```
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: multiLineCode),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GenAiStandardCodeBlock), findsOneWidget);
    expect(find.text('PYTHON'), findsOneWidget);
    // Line numbers 1, 2, 3 should be displayed in the gutter with monospace font
    expect(find.text('1\n2\n3'), findsOneWidget);
    final lineNumbersText = tester.widget<Text>(find.text('1\n2\n3'));
    expect(lineNumbersText.style?.fontFamily, 'RobotoMono');
    expect(lineNumbersText.style?.fontFamilyFallback, contains('monospace'));
    expect(find.textContaining('return a + b'), findsOneWidget);
  });

  test('GenAiSyntaxHighlighter tokenizes Python, Dart, JS, JSON, SQL, Bash',
      () {
    const highlighter = GenAiSyntaxHighlighter(brightness: Brightness.dark);
    final theme = SyntaxTheme.dark;

    // Python
    final pySpans = highlighter.highlight(
      code: 'def add(x: int) -> str:\n    # comment\n    return "hi" + str(x)',
      language: 'python',
    );
    expect(pySpans.first.style?.fontFamily, 'RobotoMono');
    expect(pySpans.first.style?.fontFamilyFallback, contains('monospace'));
    expect(
      pySpans.any((s) => s.text == 'def' && s.style?.color == theme.keyword),
      isTrue,
    );
    expect(
      pySpans.any(
        (s) => s.text == 'return' && s.style?.color == theme.keyword,
      ),
      isTrue,
    );
    expect(
      pySpans.any(
        (s) => s.text == '# comment' && s.style?.color == theme.comment,
      ),
      isTrue,
    );
    expect(
      pySpans.any((s) => s.text == '"hi"' && s.style?.color == theme.string),
      isTrue,
    );

    // Dart
    final dartSpans = highlighter.highlight(
      code:
          'class MyWidget extends StatelessWidget {\n  final int count = 42;\n}',
      language: 'dart',
    );
    expect(
      dartSpans.any(
        (s) => s.text == 'class' && s.style?.color == theme.keyword,
      ),
      isTrue,
    );
    expect(
      dartSpans.any(
        (s) => s.text == 'final' && s.style?.color == theme.keyword,
      ),
      isTrue,
    );
    expect(
      dartSpans.any((s) => s.text == 'int' && s.style?.color == theme.type),
      isTrue,
    );
    expect(
      dartSpans.any((s) => s.text == '42' && s.style?.color == theme.number),
      isTrue,
    );

    // JSON
    final jsonSpans = highlighter.highlight(
      code: '{\n  "name": "TechPie",\n  "count": 100\n}',
      language: 'json',
    );
    expect(
      jsonSpans.any(
        (s) => s.text == '"name"' && s.style?.color == theme.property,
      ),
      isTrue,
    );
    expect(
      jsonSpans.any(
        (s) => s.text == '"TechPie"' && s.style?.color == theme.string,
      ),
      isTrue,
    );
    expect(
      jsonSpans.any(
        (s) => s.text == '100' && s.style?.color == theme.number,
      ),
      isTrue,
    );

    // SQL
    final sqlSpans = highlighter.highlight(
      code: 'SELECT id, username FROM users WHERE age >= 18;',
      language: 'sql',
    );
    expect(
      sqlSpans.any(
        (s) => s.text == 'SELECT' && s.style?.color == theme.keyword,
      ),
      isTrue,
    );
    expect(
      sqlSpans.any((s) => s.text == 'FROM' && s.style?.color == theme.keyword),
      isTrue,
    );
    expect(
      sqlSpans.any(
        (s) => s.text == 'WHERE' && s.style?.color == theme.keyword,
      ),
      isTrue,
    );

    // Bash
    final bashSpans = highlighter.highlight(
      code: 'echo "Hello \$USER"\n# deploy script',
      language: 'bash',
    );
    expect(
      bashSpans.any(
        (s) => s.text == 'echo' && s.style?.color == theme.keyword,
      ),
      isTrue,
    );
    expect(
      bashSpans.any(
        (s) => s.text == '# deploy script' && s.style?.color == theme.comment,
      ),
      isTrue,
    );
  });

  testWidgets(
      'renders Markdown typography with headings, blockquotes, and tables',
      (tester) async {
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
    final selectable =
        tester.widgetList<SelectableText>(selectableFinder).firstWhere(
              (w) => w.textSpan?.toPlainText().contains('黑暗模式下的引用块内容') ?? false,
            );
    final resolvedStyle = selectable.textSpan?.style ??
        ((selectable.textSpan?.children?.isNotEmpty ?? false)
            ? (selectable.textSpan!.children!.first as TextSpan).style
            : null);
    expect(resolvedStyle?.color, darkTheme.colorScheme.onSurfaceVariant);

    final decoratedBoxes =
        tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
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

  testWidgets('renders task list checkboxes and tables with various alignments',
      (tester) async {
    const listAndTableMarkdown = '''
- [x] 已完成项测试
- [ ] 未完成项测试

| 姓名 | 年龄 | 角色 | 状态 |
| :--- | :---: | ---: | :--- |
| 张三 | 20 | 开发者 | 正常 |
| 李四 | 22 | 测试者 | 活跃 |
''';

    await tester.pumpWidget(
      buildApp(
        const GenAiMarkdown(data: listAndTableMarkdown),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已完成项测试'), findsOneWidget);
    expect(find.textContaining('未完成项测试'), findsOneWidget);
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('李四'), findsOneWidget);
    expect(find.text('开发者'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles edge-case markdown inputs gracefully without crashing',
      (tester) async {
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
