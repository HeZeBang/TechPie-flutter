import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'markdown/genai_markdown.dart';

class GenAiThinkingView extends StatefulWidget {
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
  State<GenAiThinkingView> createState() => _GenAiThinkingViewState();
}

class _GenAiThinkingViewState extends State<GenAiThinkingView> {
  late bool _expanded = widget.initiallyExpanded ||
      widget.autoExpandWhileThinking && widget.isThinking;

  @override
  void didUpdateWidget(covariant GenAiThinkingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoExpandWhileThinking &&
        !oldWidget.isThinking &&
        widget.isThinking) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reasoning.isEmpty && !widget.isThinking) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;

    final title = widget.isThinking
        ? '正在深度思考…'
        : (widget.durationMs != null
            ? '已深度思考 (${(widget.durationMs! / 1000).toStringAsFixed(1)} 秒)'
            : '已完成深度思考');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  children: [
                    if (widget.isThinking)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: accent,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.psychology_outlined,
                          size: 18,
                          color: muted,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: widget.isThinking ? accent : muted,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded && widget.reasoning.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(34, 0, 8, 8),
                child: GenAiMarkdown(
                  data: widget.reasoning,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                  onTapLink: (_, href, __) {
                    if (href != null) widget.onTapLink?.call(href);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
