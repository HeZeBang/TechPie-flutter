import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'genai_code_block.dart';
import 'genai_latex.dart';

export 'genai_chart_view.dart';
export 'genai_code_block.dart';
export 'genai_latex.dart';
export 'genai_mermaid_view.dart';
export 'genai_syntax_highlighter.dart';

const List<String> kGenAiMonospaceFallback = [
  'JetBrains Mono',
  'Fira Code',
  'Cascadia Code',
  'Menlo',
  'Monaco',
  'Consolas',
  'Courier New',
  'monospace',
];

/// An advanced Markdown renderer with LaTeX math, interactive Charts, Mermaid diagrams,
/// and syntax code blocks.
class GenAiMarkdown extends StatelessWidget {
  const GenAiMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.styleSheet,
    this.imageBuilder,
    this.onTapLink,
  });

  final String data;
  final bool selectable;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownImageBuilder? imageBuilder;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    final baseStyle = styleSheet ?? MarkdownStyleSheet.fromTheme(theme);
    final effectiveStyleSheet = baseStyle.copyWith(
      p: baseStyle.p ??
          const TextStyle(
            fontSize: 14,
            height: 1.75,
          ),
      h1: baseStyle.h1 ??
          const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.4,
            letterSpacing: -0.3,
          ),
      h2: baseStyle.h2 ??
          const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.4,
            letterSpacing: -0.2,
          ),
      h3: baseStyle.h3 ??
          const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
      h4: baseStyle.h4 ??
          const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
      h5: baseStyle.h5 ??
          const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
      h6: baseStyle.h6 ??
          const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
      blockquote: baseStyle.blockquote ??
          TextStyle(
            fontSize: 13.5,
            height: 1.65,
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: .85),
            fontStyle: FontStyle.italic,
          ),
      blockquoteDecoration: baseStyle.blockquoteDecoration ??
          BoxDecoration(
            border: Border(
              left: BorderSide(
                color: accent.withValues(alpha: .6),
                width: 3.5,
              ),
            ),
            color: accent.withValues(alpha: .04),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
      blockquotePadding: baseStyle.blockquotePadding ??
          const EdgeInsets.fromLTRB(14, 8, 12, 8),
      code: baseStyle.code ??
          TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: kGenAiMonospaceFallback,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: accent,
            backgroundColor: accent.withValues(alpha: .08),
          ),
      tableHead: baseStyle.tableHead ??
          const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
      tableBody: baseStyle.tableBody ??
          const TextStyle(
            fontSize: 13,
            height: 1.5,
          ),
      tableBorder: baseStyle.tableBorder ??
          TableBorder.all(
            color: isDark
                ? Colors.white.withValues(alpha: .12)
                : Colors.black.withValues(alpha: .1),
            width: 1,
            borderRadius: BorderRadius.circular(6),
          ),
      tableCellsPadding: baseStyle.tableCellsPadding ??
          const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      listBullet: baseStyle.listBullet ??
          TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
    );

    return MarkdownBody(
      data: preprocessLatexBlocks(data),
      selectable: selectable,
      extensionSet: md.ExtensionSet.gitHubWeb,
      inlineSyntaxes: [LatexInlineSyntax()],
      builders: {
        'latex-inline': GenAiLatexInlineBuilder(),
        'pre': GenAiPreBuilder(),
      },
      styleSheet: effectiveStyleSheet,
      imageBuilder: imageBuilder,
      onTapLink: onTapLink,
    );
  }
}
