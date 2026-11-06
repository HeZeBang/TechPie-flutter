import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../genai_icons.dart';
import '../genai_theme.dart';
import 'genai_chart_view.dart';
import 'genai_code_font.dart';
import 'genai_copy_button.dart';
import 'genai_latex.dart';
import 'genai_mermaid_view.dart';
import 'genai_syntax_highlighter.dart';

/// Pre builder that routes code blocks to Mermaid, Chart, LaTeX, or standard code block.
class GenAiPreBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return const SizedBox.shrink();
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final (language, code) = _extractCodeInfo(element);

    if (code.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final lang = language?.toLowerCase().trim() ?? '';

    // 1. Mermaid diagram
    if (lang == 'mermaid') {
      return GenAiMermaidView(code: code);
    }

    // 2. Chart
    if (lang == 'chart' ||
        lang == 'fl_chart' ||
        lang.startsWith('chart:') ||
        lang.startsWith('chart-')) {
      String? typeHint;
      if (lang.startsWith('chart:')) {
        typeHint = lang.substring('chart:'.length);
      } else if (lang.startsWith('chart-')) {
        typeHint = lang.substring('chart-'.length);
      }
      return GenAiChartView(code: code, typeHint: typeHint);
    }

    // 3. LaTeX / Math
    if (lang == 'latex' || lang == 'tex' || lang == 'math') {
      return GenAiLatexBlockView(formula: code);
    }

    // 4. Standard programming code block
    return GenAiStandardCodeBlock(
      code: code,
      language: language,
    );
  }

  (String?, String) _extractCodeInfo(md.Element element) {
    String? language;
    var code = element.textContent;

    if (element.children != null && element.children!.isNotEmpty) {
      final firstChild = element.children!.first;
      if (firstChild is md.Element) {
        final className = firstChild.attributes['class'];
        if (className != null && className.startsWith('language-')) {
          language = className.substring('language-'.length);
        }
        code = firstChild.textContent;
      }
    }

    // Trim trailing newline added by markdown parser
    if (code.endsWith('\n')) {
      code = code.substring(0, code.length - 1);
    }

    return (language, code);
  }
}

/// A standard code block with language indicator and copy-to-clipboard button.
class GenAiStandardCodeBlock extends StatefulWidget {
  const GenAiStandardCodeBlock({
    super.key,
    required this.code,
    this.language,
  });

  final String code;
  final String? language;

  @override
  State<GenAiStandardCodeBlock> createState() => _GenAiStandardCodeBlockState();
}

class _GenAiStandardCodeBlockState extends State<GenAiStandardCodeBlock> {
  (String, String?, Brightness, TextStyle)? _highlightKey;
  List<TextSpan> _spans = const [];
  String get code => widget.code;
  String? get language => widget.language;

  List<TextSpan> _highlight(Brightness brightness, TextStyle style) {
    final key = (code, language, brightness, style);
    if (_highlightKey != key) {
      _spans = GenAiSyntaxHighlighter(brightness: brightness).highlight(
        code: code,
        language: language,
        baseStyle: style,
      );
      _highlightKey = key;
    }
    return _spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = GenAiPalette.of(context);
    final rawLang = language?.trim();
    final displayLang = (rawLang != null && rawLang.isNotEmpty) ? rawLang.toUpperCase() : '代码';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GenAiContentHeader(
            title: displayLang,
            leading: GenAiIcon(GenAiGlyph.code, size: 15, color: palette.muted),
            actions: [
              SizedBox(
                height: 36,
                child: GenAiCopyButton(text: code, tooltip: '复制代码', showLabel: false),
              ),
            ],
          ),

          // Code Body
          Builder(
            builder: (context) {
              final baseCodeStyle = TextStyle(
                fontFamily: kGenAiMonospaceFamily,
                fontFamilyFallback: kGenAiMonospaceFallback,
                fontSize: 13,
                height: 1.7,
                color: palette.text.withValues(alpha: .9),
              );
              // Gutter numbers and code share one strut and one text-height
              // policy so a CJK fallback in the code cannot shift its baselines
              // relative to the line numbers.
              const codeStrut = StrutStyle(
                fontFamily: kGenAiMonospaceFamily,
                fontFamilyFallback: kGenAiMonospaceFallback,
                fontSize: 13,
                height: 1.7,
                forceStrutHeight: true,
              );
              const codeTextHeightBehavior = TextHeightBehavior();
              final spans = _highlight(theme.brightness, baseCodeStyle);
              final lineCount = '\n'.allMatches(code).length + 1;
              final showLineNumbers = lineCount > 1;

              return Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: showLineNumbers ? 0 : 14,
                ),
                child: showLineNumbers
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 14, right: 10),
                            child: Text(
                              List.generate(lineCount, (i) => '${i + 1}').join('\n'),
                              key: const ValueKey('genai-code-gutter'),
                              textAlign: TextAlign.right,
                              strutStyle: codeStrut,
                              textHeightBehavior: codeTextHeightBehavior,
                              style: TextStyle(
                                fontFamily: kGenAiMonospaceFamily,
                                fontFamilyFallback: kGenAiMonospaceFallback,
                                fontSize: 13,
                                height: 1.7,
                                color: palette.muted.withValues(alpha: .55),
                              ),
                            ),
                          ),
                          Container(width: 1, color: palette.line),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: SelectableText.rich(
                                TextSpan(children: spans),
                                key: const ValueKey('genai-code-content'),
                                style: baseCodeStyle,
                                strutStyle: codeStrut,
                                textHeightBehavior: codeTextHeightBehavior,
                              ),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText.rich(
                          TextSpan(children: spans),
                          key: const ValueKey('genai-code-content'),
                          style: baseCodeStyle,
                          strutStyle: codeStrut,
                          textHeightBehavior: codeTextHeightBehavior,
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}
