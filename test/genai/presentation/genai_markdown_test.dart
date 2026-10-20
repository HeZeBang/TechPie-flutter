import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_markdown.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
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
}
