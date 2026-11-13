import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
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

  test('display math retains quote and list containers without treating markers as TeX', () {
    const source = '> Before\n> \\[\n> A=U\\Sigma V^T\n> \\]\n> After';
    final nodes = md.Document().parseLines(preprocessLatexBlocks(source).split('\n'));
    final quote = nodes.whereType<md.Element>().single;
    expect(quote.tag, 'blockquote');
    expect(quote.textContent, contains(r'A=U\Sigma V^T'));
    expect(quote.textContent, isNot(contains('>')));

    const list = '1. Before\n\n   \\[x^2\\]\n\n   After';
    final listNodes = md.Document().parseLines(preprocessLatexBlocks(list).split('\n'));
    expect(listNodes.whereType<md.Element>().single.tag, 'ol');
    const code = '> ```text\n> \\[literal\\]\n> ```';
    expect(preprocessLatexBlocks(code), code);
  });

  test('delimiter stripping applies the ordered rules exactly once', () {
    // Display pairs first, then the inline single-dollar rule.
    expect(stripLatexDelimiters(r'  $$ x $$  '), 'x');
    expect(stripLatexDelimiters(r'\[ y \]'), 'y');
    expect(stripLatexDelimiters(r'\( z \)'), 'z');
    expect(stripLatexDelimiters(r'$ w $'), 'w');

    // Only the first matching rule runs, so one call removes one layer.
    expect(stripLatexDelimiters(r'$$\[x\]$$'), r'\[x\]');
    expect(stripLatexDelimiters(r'$$$$\frac{1}{2}$$$$'), r'$$\frac{1}{2}$$');

    // Short and empty bodies behave as before: trim, then leave unmatched.
    expect(stripLatexDelimiters('  '), '');
    expect(stripLatexDelimiters(r'$$'), '');
    expect(stripLatexDelimiters(r'$$  $$'), '');
    expect(stripLatexDelimiters('plain'), 'plain');
    expect(stripLatexDelimiters(r'\[unclosed'), r'\[unclosed');
    expect(stripLatexDelimiters(r'end$$'), r'end$$');
  });

  testWidgets('empty inline math advances the parser during streaming and replay', (tester) async {
    for (final literal in [r'\( \)', '\\( \t \\)']) {
      final parser = md.InlineParser(literal, md.Document());
      expect(LatexInlineSyntax().tryMatch(parser), isTrue);
      // Check progress before invoking the full parser: a regression must fail
      // this assertion instead of hanging the test runner in its parse loop.
      expect(parser.pos, literal.length);
    }

    // Reduced from the saved Kimi-K3 reasoning that locked the browser.
    const source = r'Wait note uses \( \) directly in HTML text. Then \(x^2\).';
    for (var end = 1; end <= source.length; end++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GenAiMarkdown(data: source.substring(0, end))),
        ),
      );
      expect(tester.takeException(), isNull);
    }
    expect(find.textContaining(r'\( \)', findRichText: true), findsWidgets);
    expect(find.byType(Math), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GenAiMarkdown(data: source)),
      ),
    );
    expect(find.textContaining(r'\( \)', findRichText: true), findsWidgets);
    expect(find.byType(Math), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('parenthesized and bracketed LaTeX never reach the text layer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenAiMarkdown(
            data: r'Before \(a+b\) after.'
                '\n\n'
                r'\[c^2\]'
                '\n\n'
                '```latex\n'
                r'\(d\)'
                '\n```',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Math), findsNWidgets(3));
    expect(find.byType(GenAiLatexBlockView), findsNWidgets(2));
    expect(find.textContaining(r'\(a+b\)', findRichText: true), findsNothing);
    expect(find.textContaining(r'\[c^2\]', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
