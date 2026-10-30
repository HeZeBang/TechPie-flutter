import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_markdown.dart';

void main() {
  test('display math preprocessing preserves code spans and escaped delimiters', () {
    const examples = r'Use ``a ` $$x$$ \[y\]`` and \$\$x\$\$ and \\[y\\] literally.';
    final result = preprocessLatexBlocks('$examples\n\n' r'\[z^2\].');

    expect(result, startsWith(examples));
    expect('```latex'.allMatches(result), hasLength(1));
    expect(result, contains('```latex\nz^2.\n```'));
  });

  test('complete and streamed source fences retain their original math text', () {
    for (final fence in ['```', '~~~~']) {
      final source = '$fence'
          'techpie-visual\n'
          r'<span data-latex="\frac{1}{2}"></span>'
          '\n'
          r'<script>const label = "$$x$$";</script>';
      expect(preprocessLatexBlocks(source), source);
      expect(preprocessLatexBlocks('$source\n$fence'), '$source\n$fence');
    }
  });

  test('escaped closing dollars do not truncate a display formula', () {
    final result = preprocessLatexBlocks(r'$$x + \$$ + y$$');
    expect(result, contains('```latex\n' r'x + \$$ + y' '\n```'));
    expect('```latex'.allMatches(result), hasLength(1));
  });

  test('backslashes inside code do not escape its closing backticks', () {
    final result = preprocessLatexBlocks(r'Use `path\` then $$x^2$$.');
    expect(result, startsWith(r'Use `path\` then '));
    expect(result, contains('```latex\nx^2.\n```'));
  });

  testWidgets('inline parentheses and dollars render beside literal math code', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenAiMarkdown(
            data: r'Inline \(x^2\) and $y$. Use `$$z$$` and `\[z\]` literally.'
                '\n\n'
                r'\[\frac{1}{2}mv^2\]',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(3));
    expect(find.byType(GenAiLatexBlockView), findsOneWidget);
    expect(find.textContaining(r'$$z$$', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
