import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../genai_image.dart';
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
    // Shared reading rhythm for prose, lists and tables, without adding a
    // paragraph inset inside every list item.
    final effectiveStyleSheet = baseStyle.copyWith(
      blockSpacing: styleSheet?.blockSpacing ?? 12,
      pPadding: styleSheet?.pPadding ?? EdgeInsets.zero,
      p: TextStyle(
        fontSize: compact ? 14 : 15,
        height: 1.6,
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
            height: 1.6,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      blockquoteDecoration: styleSheet?.blockquoteDecoration ??
          BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isDark
                    ? theme.colorScheme.outline.withValues(alpha: .5)
                    : theme.colorScheme.outlineVariant,
                width: 2,
              ),
            ),
          ),
      blockquotePadding: styleSheet?.blockquotePadding ?? const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
        fontSize: compact ? 13 : 14,
        height: 1.6,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.tableHead),
      tableBody: TextStyle(
        fontSize: compact ? 13 : 14,
        height: 1.6,
        leadingDistribution: TextLeadingDistribution.even,
        color: theme.colorScheme.onSurface,
      ).merge(styleSheet?.tableBody),
      tableColumnWidth: styleSheet?.tableColumnWidth ?? const _ReadableTableColumnWidth(),
      tableScrollbarThumbVisibility: true,
      tableHeadAlign: styleSheet?.tableHeadAlign ?? TextAlign.left,
      tablePadding: styleSheet?.tablePadding ?? const EdgeInsets.only(top: 4, bottom: 12),
      tableBorder: styleSheet?.tableBorder ??
          TableBorder(
            horizontalInside: BorderSide(color: tableLineColor, width: 1),
            bottom: BorderSide(color: tableLineColor, width: 1),
          ),
      tableCellsPadding:
          styleSheet?.tableCellsPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      strong: const TextStyle(fontWeight: FontWeight.w700).merge(styleSheet?.strong),
      // Separate the marker from its content (including multi-digit numbers),
      // while sharing the first line's font metrics and accessibility scaling.
      listIndent: styleSheet?.listIndent ?? 24,
      listBulletPadding: styleSheet?.listBulletPadding ?? const EdgeInsets.only(right: 10),
      listBullet: TextStyle(
        fontSize: compact ? 14 : 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
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

    // One SelectionArea owns prose selection; inner Markdown spans remain
    // non-selectable to avoid competing selection regions.
    final body = _GenAiMarkdownBody(
      data: data,
      selectable: false,
      interactiveVisuals: interactiveVisuals,
      styleSheet: effectiveStyleSheet,
      imageBuilder: imageBuilder ?? _buildMarkdownImage,
      onTapLink: onTapLink,
    );

    return _MarkdownSelection(
      enabled: selectable,
      styleSheet: effectiveStyleSheet,
      latestVisual: latestVisual,
      answerId: visualAnswerId,
      child: body,
    );
  }
}

/// A fullscreen visual owns interaction until it closes. Suspend background
/// prose selection without replacing the document or its running visuals.
class _MarkdownSelection extends StatefulWidget {
  const _MarkdownSelection({
    required this.enabled,
    required this.styleSheet,
    required this.latestVisual,
    required this.answerId,
    required this.child,
  });

  final bool enabled;
  final MarkdownStyleSheet styleSheet;
  final (String, int)? latestVisual;
  final String answerId;
  final Widget child;

  @override
  State<_MarkdownSelection> createState() => _MarkdownSelectionState();
}

class _MarkdownSelectionState extends State<_MarkdownSelection> {
  StaticSelectionContainerDelegate _selection = StaticSelectionContainerDelegate();
  bool _fullscreen = false;

  @override
  void didUpdateWidget(_MarkdownSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.styleSheet != oldWidget.styleSheet) {
      // MarkdownBuilder replaces keyed spans when typography changes. Start a
      // fresh registrar without reparenting the document or its platform views.
      final previous = _selection;
      _selection = StaticSelectionContainerDelegate();
      // Descendants unregister from the old delegate during this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = DefaultTextHeightBehavior(
      textHeightBehavior: const TextHeightBehavior(
        leadingDistribution: TextLeadingDistribution.even,
      ),
      child: widget.child,
    );
    return GenAiVisualScope(
      latest: widget.latestVisual,
      answerId: widget.answerId,
      onFullscreenChanged: (value) {
        if (_fullscreen != value) setState(() => _fullscreen = value);
      },
      child: widget.enabled
          ? SelectionArea(
              child: _fullscreen
                  ? SelectionContainer.disabled(child: body)
                  : SelectionContainer(delegate: _selection, child: body),
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
      bulletBuilder: (parameters) {
        final unordered = parameters.style == BulletStyle.unorderedList;
        final style = widget.styleSheet.listBullet!;
        // List markers are layout, not part of the selectable prose.
        return SelectionContainer.disabled(
          child: Text(
            unordered ? '•' : '${parameters.index + 1}.',
            textAlign: TextAlign.right,
            // Enlarge dots while retaining the body's line box and numbers.
            style: unordered
                ? style.copyWith(
                    fontSize: (style.fontSize ?? 15) * 1.2,
                    height: (style.height ?? 1.6) / 1.2,
                  )
                : style,
          ),
        );
      },
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

/// Keep short columns compact and long prose readable without forcing the
/// entire table into the chat width. Markdown owns scrolling and its controller.
class _ReadableTableColumnWidth extends IntrinsicColumnWidth {
  const _ReadableTableColumnWidth();

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      super.minIntrinsicWidth(cells, containerWidth).clamp(48.0, 280.0);

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      super.maxIntrinsicWidth(cells, containerWidth).clamp(48.0, 280.0);
}
