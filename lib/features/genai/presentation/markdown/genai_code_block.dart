import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'genai_chart_view.dart';
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
  bool _copied = false;

  Future<void> _copyCode() async {
    setState(() => _copied = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.code));
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: .08)
        : Colors.black.withValues(alpha: .06);
    final cardBg = isDark
        ? Colors.white.withValues(alpha: .03)
        : Colors.black.withValues(alpha: .025);
    final rawLang = widget.language?.trim();
    final displayLang = (rawLang != null && rawLang.isNotEmpty)
        ? rawLang.toUpperCase()
        : 'CODE';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: .06)
                      : Colors.black.withValues(alpha: .04),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    displayLang,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: _copied ? '已复制' : '复制代码',
                  child: InkWell(
                    onTap: _copyCode,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                            size: 13,
                            color: _copied
                                ? theme.colorScheme.primary
                                : theme.hintColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _copied ? '已复制' : '复制',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _copied
                                  ? theme.colorScheme.primary
                                  : theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Code Body
          Builder(
            builder: (context) {
              final highlighter =
                  GenAiSyntaxHighlighter(brightness: theme.brightness);
              const monospaceFallback = [
                'JetBrains Mono',
                'Fira Code',
                'Cascadia Code',
                'Menlo',
                'Monaco',
                'Consolas',
                'Courier New',
                'monospace',
              ];
              final baseCodeStyle = TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: monospaceFallback,
                fontSize: 12.5,
                height: 1.6,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: .9),
              );
              final spans = highlighter.highlight(
                code: widget.code,
                language: widget.language,
                baseStyle: baseCodeStyle,
              );
              final lineCount = '\n'.allMatches(widget.code).length + 1;
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
                              List.generate(lineCount, (i) => '${i + 1}')
                                  .join('\n'),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontFamilyFallback: monospaceFallback,
                                fontSize: 12.5,
                                height: 1.6,
                                color: theme.hintColor.withValues(alpha: .35),
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            color: isDark
                                ? Colors.white.withValues(alpha: .06)
                                : Colors.black.withValues(alpha: .04),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: SelectableText.rich(
                                TextSpan(children: spans),
                                style: baseCodeStyle,
                              ),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText.rich(
                          TextSpan(children: spans),
                          style: baseCodeStyle,
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
