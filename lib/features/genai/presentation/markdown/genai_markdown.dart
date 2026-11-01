import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../genai_image.dart';
import '../genai_theme.dart';
import '../visuals/genai_visual_syntax.dart';
import '../visuals/genai_visual_view.dart';
import 'genai_code_block.dart';
import 'genai_code_font.dart';
import 'genai_latex.dart';

export 'genai_chart_view.dart';
export 'genai_code_block.dart';
export 'genai_latex.dart';
export 'genai_mermaid_view.dart';
export 'genai_syntax_highlighter.dart';

/// An advanced Markdown renderer with LaTeX math, interactive Charts, Mermaid diagrams,
/// and syntax code blocks.
class GenAiMarkdown extends StatelessWidget {
  const GenAiMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.compact = false,
    this.interactiveVisuals = false,
    this.latestVisual,
    this.visualAnswerId = '',
    this.styleSheet,
    this.imageBuilder,
    this.onTapLink,
  });

  final String data;
  final bool selectable;
  final bool compact;
  final bool interactiveVisuals;
  final (String, int)? latestVisual;
  final String visualAnswerId;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownImageBuilder? imageBuilder;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    // The draft separates table rows with a single hairline (--line), not a
    // full grid.
    final tableLineColor =
        isDark ? Colors.white.withValues(alpha: .14) : Colors.black.withValues(alpha: .12);

    // Always retain the complete theme sheet: MarkdownBuilder requires styles
    // for inline emphasis, links, tables and lists even on compact screens.
    final baseStyle = MarkdownStyleSheet.fromTheme(theme).merge(styleSheet);
    // The draft's thread runs at 15/1.75, gives paragraphs an 18px bottom
    // margin and spaces every other block by 13px (its h2 margins). The
    // paragraph padding below tops the block spacing up to 18.
    final effectiveStyleSheet = baseStyle.copyWith(
      blockSpacing: styleSheet?.blockSpacing ?? 13,
      pPadding: styleSheet?.pPadding ?? const EdgeInsets.only(bottom: 5),
      p: TextStyle(
        fontSize: compact ? 14 : 15,
        height: 1.75,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.p),
      // Merge individual text styles, not whole nullable heading styles: a
      // compact/color-only override must not discard the draft's 600 weight.
      h1: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.4,
        leadingDistribution: TextLeadingDistribution.even,
        letterSpacing: -0.3,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.h1),
      h2: TextStyle(
        fontSize: compact ? 20 : 21,
        fontWeight: FontWeight.w600,
        height: 1.4,
        leadingDistribution: TextLeadingDistribution.even,
        letterSpacing: -0.3,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.h2),
      h3: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.4,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.h3),
      h4: TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        height: 1.4,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.h4),
      h5: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        height: 1.4,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.h5),
      h6: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        height: 1.4,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurfaceVariant,
      ).merge(styleSheet?.h6),
      blockquote: styleSheet?.blockquote ??
          TextStyle(
            fontSize: compact ? 14 : 15,
            height: 1.75,
            color: accent,
          ),
      blockquoteDecoration: styleSheet?.blockquoteDecoration ??
          BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isDark
                    ? theme.colorScheme.outline.withValues(alpha: .5)
                    : theme.colorScheme.outlineVariant,
                width: 3.5,
              ),
            ),
            color: isDark
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .28)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: .38),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
      blockquotePadding: styleSheet?.blockquotePadding ?? const EdgeInsets.fromLTRB(16, 10, 16, 10),
      code: styleSheet?.code ??
          TextStyle(
            fontFamily: kGenAiMonospaceFamily,
            fontFamilyFallback: kGenAiMonospaceFallback,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFFFFB4AB) : accent,
            backgroundColor:
                isDark ? Colors.white.withValues(alpha: .08) : accent.withValues(alpha: .08),
          ),
      // Only activity tables use .step th { font-weight:400 } in the draft.
      // Answer tables retain the browser's bold <th> default.
      tableHead: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        height: 1.75,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.tableHead),
      tableBody: TextStyle(
        fontSize: 12,
        height: 1.75,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.tableBody),
      tableHeadAlign: styleSheet?.tableHeadAlign ?? TextAlign.left,
      tablePadding: styleSheet?.tablePadding ?? const EdgeInsets.symmetric(vertical: 4),
      tableBorder: styleSheet?.tableBorder ??
          TableBorder(
            horizontalInside: BorderSide(color: tableLineColor, width: 1),
            bottom: BorderSide(color: tableLineColor, width: 1),
          ),
      tableCellsPadding:
          styleSheet?.tableCellsPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      strong: const TextStyle(fontWeight: FontWeight.w700).merge(styleSheet?.strong),
      // The draft leaves answer ul/ol at the browser defaults (40px indent,
      // normal-weight markers inheriting the thread's 14/15px type and 1.75
      // line-height). Give markers the same leading as the first content line
      // rather than inheriting Material bodyMedium's different line metrics.
      listIndent: styleSheet?.listIndent ?? 40,
      listBulletPadding: styleSheet?.listBulletPadding ?? EdgeInsets.zero,
      listBullet: TextStyle(
        fontSize: compact ? 14 : 15,
        fontWeight: FontWeight.w400,
        height: 1.75,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.p).merge(styleSheet?.listBullet),
      horizontalRuleDecoration: styleSheet?.horizontalRuleDecoration ??
          BoxDecoration(
            border: Border(
              top: BorderSide(
                width: 1.5,
                color: isDark
                    ? Colors.white.withValues(alpha: .12)
                    : Colors.black.withValues(alpha: .1),
              ),
            ),
          ),
      checkbox: styleSheet?.checkbox ?? TextStyle(color: accent),
      a: styleSheet?.a ??
          TextStyle(
            color: accent,
            decoration: TextDecoration.underline,
            decorationColor: accent.withValues(alpha: .5),
          ),
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
    );

    // flutter_markdown 0.7.6's MarkdownBuilder exposes no contextMenuBuilder
    // hook: selectable: true builds a bare SelectableText whose menu cannot be
    // themed. A SelectionArea owns prose selection instead, so the body is
    // always built non-selectable to avoid a competing inner selection region.
    // No caller places GenAiMarkdown inside a SelectionArea, so this does not
    // nest selection areas.
    final body = _GenAiMarkdownBody(
      data: data,
      selectable: false,
      interactiveVisuals: interactiveVisuals,
      styleSheet: effectiveStyleSheet,
      imageBuilder: imageBuilder ?? _buildMarkdownImage,
      onTapLink: onTapLink,
    );

    return GenAiVisualScope(
      latest: latestVisual,
      answerId: visualAnswerId,
      child: selectable
          ? SelectionArea(
              contextMenuBuilder: genAiRegionSelectionContextMenu,
              child: DefaultTextHeightBehavior(
                textHeightBehavior: const TextHeightBehavior(
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                child: body,
              ),
            )
          : body,
    );
  }
}

Widget _buildMarkdownImage(Uri uri, String? title, String? alt) => GenAiMarkdownImage(
      uri: uri,
      title: title,
      alt: alt,
    );

class _GenAiMarkdownBody extends StatefulWidget {
  const _GenAiMarkdownBody({
    required this.data,
    required this.selectable,
    required this.styleSheet,
    this.imageBuilder,
    this.onTapLink,
    required this.interactiveVisuals,
  });

  final String data;
  final bool selectable;
  final MarkdownStyleSheet styleSheet;
  final MarkdownImageBuilder? imageBuilder;
  final MarkdownTapLinkCallback? onTapLink;
  final bool interactiveVisuals;

  @override
  State<_GenAiMarkdownBody> createState() => _GenAiMarkdownBodyState();
}

class _GenAiMarkdownBodyState extends State<_GenAiMarkdownBody> implements MarkdownBuilderDelegate {
  List<md.Node>? _astNodes;
  Widget? _content;
  bool _needsBuild = true;
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _needsBuild = true;
  }

  @override
  void didUpdateWidget(_GenAiMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data ||
        widget.interactiveVisuals != oldWidget.interactiveVisuals) {
      _astNodes = null;
    }
    if (widget.data != oldWidget.data ||
        widget.styleSheet != oldWidget.styleSheet ||
        widget.selectable != oldWidget.selectable ||
        widget.interactiveVisuals != oldWidget.interactiveVisuals ||
        widget.imageBuilder != oldWidget.imageBuilder) {
      _needsBuild = true;
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    if (_recognizers.isEmpty) {
      return;
    }
    final local = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    for (final r in local) {
      r.dispose();
    }
  }

  List<md.Node> _parseMarkdown() {
    final document = md.Document(
      inlineSyntaxes: [LatexInlineSyntax()],
      blockSyntaxes: [if (widget.interactiveVisuals) GenAiVisualSyntax()],
      extensionSet: md.ExtensionSet.gitHubWeb,
      encodeHtml: false,
    );

    final lines = const LineSplitter().convert(preprocessLatexBlocks(widget.data));
    final astNodes = document.parseLines(lines);
    void normalizeTaskItems(List<md.Node> nodes) {
      for (final node in nodes.whereType<md.Element>()) {
        final children = node.children;
        if (children == null) continue;
        // flutter_markdown 0.7.6 cannot flush an inline containing only a
        // checkbox. This occurs while streaming exactly "- [x] ".
        if (node.tag == 'li' &&
            children.length == 1 &&
            children.single is md.Element &&
            (children.single as md.Element).attributes['type'] == 'checkbox') {
          children.add(md.Text(''));
        }
        normalizeTaskItems(children);
      }
    }

    normalizeTaskItems(astNodes);
    var visualIndex = 0;
    for (final visual in GenAiVisualSyntax.elements(astNodes)) {
      visual.attributes['index'] = '${++visualIndex}';
    }
    return astNodes;
  }

  void _buildMarkdown() {
    _disposeRecognizers();

    final builder = MarkdownBuilder(
      delegate: this,
      selectable: widget.selectable,
      styleSheet: widget.styleSheet,
      imageDirectory: null,
      imageBuilder: widget.imageBuilder,
      checkboxBuilder: null,
      bulletBuilder: null,
      builders: {
        'latex-inline': GenAiLatexInlineBuilder(),
        'pre': GenAiPreBuilder(),
        if (widget.interactiveVisuals) 'techpie-visual': GenAiVisualBuilder(),
      },
      paddingBuilders: const <String, MarkdownPaddingBuilder>{},
      fitContent: true,
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
    );

    try {
      // A theme or image resolver change needs new widgets, but the parsed
      // document only depends on the source and the enabled block syntax.
      final children = builder.build(_astNodes ??= _parseMarkdown());
      _content = switch (children.length) {
        0 => const SizedBox.shrink(),
        1 => children.single,
        _ => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
      };
    } catch (_) {
      // Incomplete model output must not tear down the chat's element tree.
      _disposeRecognizers();
      _content = Text(
        widget.data,
        key: const ValueKey('genai-markdown-fallback'),
        style: widget.styleSheet.p,
      );
    }
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        if (widget.onTapLink != null) {
          widget.onTapLink!(text, href, title);
        }
      };
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    code = code.replaceAll(RegExp(r'\n$'), '');
    return TextSpan(style: styleSheet.code, text: code);
  }

  @override
  Widget build(BuildContext context) {
    if (_needsBuild) {
      _needsBuild = false;
      _buildMarkdown();
    }
    return _content!;
  }
}
