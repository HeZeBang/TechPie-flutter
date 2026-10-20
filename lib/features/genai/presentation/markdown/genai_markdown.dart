import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'genai_code_block.dart';
import 'genai_latex.dart';

export 'genai_chart_view.dart';
export 'genai_code_block.dart';
export 'genai_latex.dart';
export 'genai_mermaid_view.dart';

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

    final baseStyle = styleSheet ?? MarkdownStyleSheet.fromTheme(theme);
    final effectiveStyleSheet = baseStyle.copyWith(
      p: baseStyle.p ??
          const TextStyle(
            fontSize: 14,
            height: 1.85,
          ),
      code: baseStyle.code ??
          TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
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
