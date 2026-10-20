import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// Preprocesses raw markdown to convert `$$...$$` and `\[...\]` display math blocks
/// into clean standard ````latex` code blocks, preventing inline paragraph leakage.
String preprocessLatexBlocks(String input) {
  final parts = input.split('```');
  final buf = StringBuffer();

  for (var i = 0; i < parts.length; i++) {
    if (i.isOdd) {
      // Inside an existing code block: preserve verbatim
      buf.write('```');
      buf.write(parts[i]);
      buf.write('```');
    } else {
      // Outside code blocks: normalize block math to ```latex blocks
      var part = parts[i].replaceAll('\r\n', '\n');

      // Convert $$...$$ (with optional trailing punctuation)
      part = part.replaceAllMapped(
        RegExp(r'\$\$([\s\S]+?)\$\$([.,;!?:，。；！？]*)'),
        (match) {
          final formula = match[1]!.trim();
          final punct = match[2] ?? '';
          final formulaWithPunct = punct.isNotEmpty && !formula.endsWith(punct)
              ? '$formula$punct'
              : formula;
          return '\n\n```latex\n$formulaWithPunct\n```\n\n';
        },
      );

      // Convert \[...\] (with optional trailing punctuation)
      part = part.replaceAllMapped(
        RegExp(r'\\\[([\s\S]+?)\\\]([.,;!?:，。；！？]*)'),
        (match) {
          final formula = match[1]!.trim();
          final punct = match[2] ?? '';
          final formulaWithPunct = punct.isNotEmpty && !formula.endsWith(punct)
              ? '$formula$punct'
              : formula;
          return '\n\n```latex\n$formulaWithPunct\n```\n\n';
        },
      );

      buf.write(part);
    }
  }

  return buf.toString();
}

/// Inline syntax for LaTeX math: `$formula$` or `\(formula\)`.
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax()
      : super(r'(?:\$([^\s\$](?:[^\$\n]*?[^\s\$])?)\$|\\\((.+?)\\\))');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final inlineFormula = (match[1] ?? match[2] ?? '').trim();
    if (inlineFormula.isEmpty) {
      return false;
    }

    parser.addNode(
      md.Element.text('latex-inline', inlineFormula),
    );
    return true;
  }
}

/// Builder for inline LaTeX math.
///
/// Returns a [Text.rich] containing a [WidgetSpan], allowing the math equation
/// to flow naturally inside the paragraph without breaking into disjointed Wrap items.
class GenAiLatexInlineBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => false;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final formula = element.textContent.trim();
    if (formula.isEmpty) {
      return const SizedBox.shrink();
    }

    final textStyle =
        preferredStyle ?? parentStyle ?? Theme.of(context).textTheme.bodyMedium;

    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.alphabetic,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Math.tex(
            formula,
            mathStyle: MathStyle.text,
            textStyle: textStyle,
            onErrorFallback: (_) => Text(
              formula,
              style: (textStyle ?? const TextStyle()).copyWith(
                fontFamily: 'RobotoMono',
                fontFamilyFallback: const ['monospace', 'Menlo'],
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A clean, KaTeX-HTML style display-mode equation view.
///
/// Centered horizontally with natural padding and horizontal scrolling for wide equations,
/// without any heavy background card or visual noise.
class GenAiLatexBlockView extends StatelessWidget {
  const GenAiLatexBlockView({
    super.key,
    required this.formula,
  });

  final String formula;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 16.5,
      color: theme.textTheme.bodyMedium?.color,
    );

    var cleanFormula = formula.trim();
    if (cleanFormula.startsWith(r'$$') &&
        cleanFormula.endsWith(r'$$') &&
        cleanFormula.length >= 4) {
      cleanFormula = cleanFormula.substring(2, cleanFormula.length - 2).trim();
    } else if (cleanFormula.startsWith(r'\[') &&
        cleanFormula.endsWith(r'\]') &&
        cleanFormula.length >= 4) {
      cleanFormula = cleanFormula.substring(2, cleanFormula.length - 2).trim();
    } else if (cleanFormula.startsWith(r'$') &&
        cleanFormula.endsWith(r'$') &&
        cleanFormula.length >= 2) {
      cleanFormula = cleanFormula.substring(1, cleanFormula.length - 1).trim();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Center(
                child: Math.tex(
                  cleanFormula,
                  mathStyle: MathStyle.display,
                  textStyle: textStyle,
                  onErrorFallback: (error) => SelectableText(
                    cleanFormula,
                    style: TextStyle(
                      fontFamily: 'RobotoMono',
                      fontFamilyFallback: const ['monospace', 'Menlo'],
                      fontSize: 13,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
