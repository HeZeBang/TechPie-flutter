import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../genai_theme.dart';
import 'genai_code_font.dart';

/// Converts display math into `latex` fences without changing code examples.
String preprocessLatexBlocks(String input) {
  final output = StringBuffer();
  final prose = StringBuffer();
  String? fence;
  void flush() {
    if (prose.isNotEmpty) {
      output.write(_preprocessLatexProse(prose.toString()));
      prose.clear();
    }
  }

  for (final line in input.split('\n')) {
    final opening = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
    if (fence == null && opening != null) {
      flush();
      fence = opening.group(1)!;
      output.writeln(line);
    } else if (fence != null) {
      output.writeln(line);
      if (RegExp('^ {0,3}${fence[0]}{${fence.length},}\\s*\$').hasMatch(line)) fence = null;
    } else {
      prose.writeln(line);
    }
  }
  flush();
  final result = output.toString();
  return result.endsWith('\n') ? result.substring(0, result.length - 1) : result;
}

String _preprocessLatexProse(String input) {
  final output = StringBuffer();
  final tokens = RegExp(r'`+|\$\$|\\\[').allMatches(input).toList();
  final nextCodeEnd = <int, int>{};
  final latestCodeRun = <int, int>{};
  for (var index = tokens.length - 1; index >= 0; index--) {
    final delimiter = tokens[index][0]!;
    if (!delimiter.startsWith('`')) continue;
    final next = latestCodeRun[delimiter.length];
    if (next != null) nextCodeEnd[index] = next;
    latestCodeRun[delimiter.length] = index;
  }
  var consumed = 0;
  var literalStart = 0;
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (token.start < consumed || _isEscaped(input, token.start)) continue;
    final delimiter = token[0]!;
    if (delimiter.startsWith('`')) {
      // Code spans close only on a backtick run of exactly the same length.
      // Backslashes are literal inside code, including before the closing run.
      final next = nextCodeEnd[index];
      if (next != null) {
        consumed = tokens[next].end;
        index = next;
      }
      continue;
    }
    if (delimiter != r'$$' && delimiter != r'\[') continue;
    final closing = delimiter == r'$$' ? r'$$' : r'\]';
    final end = _unescapedDelimiter(input, closing, token.end);
    if (end == -1) continue;
    final formula = input.substring(token.end, end).trim();
    if (formula.isEmpty) continue;
    final afterFormula = end + closing.length;
    final punctuation = RegExp(r'[.,;!?:，。；！？]*').matchAsPrefix(input, afterFormula)![0]!;
    final formulaWithPunctuation =
        punctuation.isNotEmpty && !formula.endsWith(punctuation) ? '$formula$punctuation' : formula;
    output.write(input.substring(literalStart, token.start));
    output.write('\n\n```latex\n$formulaWithPunctuation\n```\n\n');
    consumed = afterFormula + punctuation.length;
    literalStart = consumed;
  }
  output.write(input.substring(literalStart));
  return output.toString();
}

int _unescapedDelimiter(String input, String delimiter, int start) {
  var position = input.indexOf(delimiter, start);
  while (position != -1) {
    if (!_isEscaped(input, position)) return position;
    position = input.indexOf(delimiter, position + delimiter.length);
  }
  return -1;
}

bool _isEscaped(String input, int position) {
  var backslashes = 0;
  for (var before = position - 1; before >= 0 && input[before] == r'\'; before--) {
    backslashes++;
  }
  return backslashes.isOdd;
}

/// Inline syntax for LaTeX math: `$formula$` or `\(formula\)`.
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax() : super(r'(?:\$([^\s\$](?:[^\$\n]*?[^\s\$])?)\$|\\\((.+?)\\\))');

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

    final baseStyle = preferredStyle ?? parentStyle ?? Theme.of(context).textTheme.bodyMedium;
    final resolvedColor = baseStyle?.color ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    // Inline math follows the paragraph's own size (never the display size),
    // so a formula keeps the line's rhythm instead of growing the row.
    final textStyle = (baseStyle ?? const TextStyle()).copyWith(
      color: resolvedColor,
      fontSize: baseStyle?.fontSize ?? 15,
    );

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
              style: textStyle.copyWith(
                fontFamily: kGenAiMonospaceFamily,
                fontFamilyFallback: kGenAiMonospaceFallback,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Strips at most one display/inline delimiter pair, in the same order the
/// renderer has always tried them, and trims the result.
///
/// Each entry is `(opening, closing, minimum length, characters per side)`.
/// Only the first matching rule applies, so a formula wrapped in two layers
/// loses exactly one layer per call, and whitespace (including an empty body)
/// is trimmed exactly as before.
String stripLatexDelimiters(String formula) {
  const rules = <(String, String, int, int)>[
    (r'$$', r'$$', 4, 2),
    (r'\[', r'\]', 4, 2),
    (r'\(', r'\)', 4, 2),
    (r'$', r'$', 2, 1),
  ];
  var cleanFormula = formula.trim();
  for (final (opening, closing, minimumLength, strip) in rules) {
    if (cleanFormula.length >= minimumLength &&
        cleanFormula.startsWith(opening) &&
        cleanFormula.endsWith(closing)) {
      return cleanFormula.substring(strip, cleanFormula.length - strip).trim();
    }
  }
  return cleanFormula;
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
      fontSize: 18,
      color: theme.textTheme.bodyMedium?.color,
    );

    final cleanFormula = stripLatexDelimiters(formula);

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
                    contextMenuBuilder: genAiTextSelectionContextMenu,
                    style: TextStyle(
                      fontFamily: kGenAiMonospaceFamily,
                      fontFamilyFallback: kGenAiMonospaceFallback,
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
