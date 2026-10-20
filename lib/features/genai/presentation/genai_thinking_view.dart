import 'package:flutter/material.dart';

import 'markdown/genai_markdown.dart';

class GenAiThinkingView extends StatefulWidget {
  const GenAiThinkingView({
    super.key,
    required this.reasoning,
    this.isThinking = false,
    this.durationMs,
    this.initiallyExpanded = false,
    this.onTapLink,
  });

  final String reasoning;
  final bool isThinking;
  final int? durationMs;
  final bool initiallyExpanded;
  final void Function(String href)? onTapLink;

  @override
  State<GenAiThinkingView> createState() => _GenAiThinkingViewState();
}

class _GenAiThinkingViewState extends State<GenAiThinkingView> {
  late bool _expanded = widget.initiallyExpanded || widget.isThinking;

  @override
  void didUpdateWidget(covariant GenAiThinkingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isThinking && widget.isThinking) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reasoning.isEmpty && !widget.isThinking) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final accent = theme.brightness == Brightness.dark
        ? const Color(0xff67d4c2)
        : const Color(0xff167c6d);
    final muted = theme.colorScheme.onSurfaceVariant;
    final border = theme.colorScheme.outlineVariant.withValues(alpha: .4);

    final title = widget.isThinking
        ? '正在深度思考…'
        : (widget.durationMs != null
            ? '已深度思考 (${(widget.durationMs! / 1000).toStringAsFixed(1)} 秒)'
            : '已完成深度思考');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    if (widget.isThinking)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 13,
                          height: 13,
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
                          size: 16,
                          color: accent,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
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
              Container(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: border.withValues(alpha: .2)),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 12,
                      color: muted.withValues(alpha: .85),
                      height: 1.6,
                      fontStyle: FontStyle.italic,
                    ),
                    child: GenAiMarkdown(
                      data: widget.reasoning,
                      selectable: true,
                      onTapLink: (_, href, __) {
                        if (href != null) widget.onTapLink?.call(href);
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
