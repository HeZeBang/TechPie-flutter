import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'genai_activity_line.dart';
import 'genai_icons.dart';
import 'genai_theme.dart';
import 'markdown/genai_markdown.dart';

/// Reasoning collapses into the same quiet activity line as tool steps.
class GenAiThinkingView extends StatelessWidget {
  const GenAiThinkingView({
    super.key,
    required this.reasoning,
    this.isThinking = false,
    this.durationMs,
    this.initiallyExpanded = false,
    this.autoExpandWhileThinking = true,
    this.onTapLink,
  });

  final String reasoning;
  final bool isThinking;
  final int? durationMs;
  final bool initiallyExpanded;
  final bool autoExpandWhileThinking;
  final void Function(String href)? onTapLink;

  @override
  Widget build(BuildContext context) {
    if (reasoning.isEmpty && !isThinking) return const SizedBox.shrink();
    final palette = GenAiPalette.of(context);
    final accent = palette.accent;
    final muted = palette.muted;
    final seconds = durationMs == null ? null : durationMs! ~/ 1000;
    final title = isThinking
        ? '正在深度思考…'
        : seconds != null
            ? '已完成思考 · ${seconds < 1 ? 1 : seconds} 秒'
            : '已完成思考';
    return GenAiDisclosure(
      // Live reasoning opens itself; finishing never collapses it under the reader.
      initiallyExpanded: initiallyExpanded,
      expandWhen: isThinking && autoExpandWhileThinking,
      color: muted,
      leading: isThinking
          ? SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: accent),
            )
          : GenAiIcon(GenAiGlyph.checkCircle, color: palette.success),
      title: title,
      children: [
        if (reasoning.isNotEmpty)
          GenAiMarkdown(
            data: reasoning,
            selectable: true,
            // Only override reasoning copy; passing the whole Material sheet
            // would also replace answer headings, lists and table defaults.
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: muted, fontSize: 13, height: 1.75),
            ),
            onTapLink: (_, href, __) {
              if (href != null) onTapLink?.call(href);
            },
          ),
      ],
    );
  }
}
