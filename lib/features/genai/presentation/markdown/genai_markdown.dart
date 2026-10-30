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
    this.interactiveVisuals = false,
    this.latestVisual,
    this.visualAnswerId = '',
    this.styleSheet,
    this.imageBuilder,
    this.onTapLink,
  });

  final String data;
  final bool selectable;
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

    final baseStyle = styleSheet ?? MarkdownStyleSheet.fromTheme(theme);
    final effectiveStyleSheet = baseStyle.copyWith(
      p: styleSheet?.p ??
          const TextStyle(
            fontSize: 15.5,
            height: 1.75,
          ),
      h1: styleSheet?.h1 ??
          TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.4,
            letterSpacing: -0.3,
            color: theme.colorScheme.onSurface,
          ),
      h2: styleSheet?.h2 ??
          TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            height: 1.4,
            letterSpacing: -0.2,
            color: theme.colorScheme.onSurface,
          ),
      h3: styleSheet?.h3 ??
          TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: theme.colorScheme.onSurface,
          ),
      h4: styleSheet?.h4 ??
          TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: theme.colorScheme.onSurface,
          ),
      h5: styleSheet?.h5 ??
          TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: theme.colorScheme.onSurface,
          ),
      h6: styleSheet?.h6 ??
          TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      blockquote: styleSheet?.blockquote ??
          TextStyle(
            fontSize: 15,
            height: 1.65,
            color: theme.colorScheme.onSurfaceVariant,
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
      tableHead: styleSheet?.tableHead ??
          TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
            color: theme.colorScheme.onSurface,
          ),
      tableBody: styleSheet?.tableBody ??
          TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: theme.colorScheme.onSurface,
          ),
      tableBorder: styleSheet?.tableBorder ??
          TableBorder.all(
            color:
                isDark ? Colors.white.withValues(alpha: .14) : Colors.black.withValues(alpha: .12),
            width: 1,
            borderRadius: BorderRadius.circular(6),
          ),
      tableCellsPadding:
          styleSheet?.tableCellsPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      listBullet: styleSheet?.listBullet ??
          TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
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

    return GenAiVisualScope(
      latest: latestVisual,
      answerId: visualAnswerId,
      child: _GenAiMarkdownBody(
        data: data,
        selectable: selectable,
        interactiveVisuals: interactiveVisuals,
        styleSheet: effectiveStyleSheet,
        imageBuilder: imageBuilder ?? _buildMarkdownImage,
        onTapLink: onTapLink,
      ),
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
