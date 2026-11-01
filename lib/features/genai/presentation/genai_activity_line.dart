import 'package:flutter/material.dart';

import 'genai_icons.dart';
import 'genai_theme.dart';

/// One quiet, expandable line for thinking, tool steps and technical detail.
/// The summary stays a single row; expanded content hangs off a thin rail.
/// The open state belongs to the widget, so streamed updates keep a user's
/// collapse choice; a new key starts from [initiallyExpanded] again.
///
/// Geometry follows the design draft's activity rows: a 12px muted summary,
/// a 15px leading glyph, a 13px chevron and a 36px minimum tap target.
class GenAiDisclosure extends StatefulWidget {
  const GenAiDisclosure({
    super.key,
    required this.leading,
    required this.title,
    required this.children,
    this.titleKey,
    this.subtitle,
    this.summary,
    this.color,
    this.initiallyExpanded = false,
    this.expandWhen = false,
    this.rail = true,
    this.dense = false,
    this.steps = false,
  });

  final Widget leading;
  final String title;
  final Key? titleKey;
  final String? subtitle;

  /// A one-line result summary shown after the subtitle on the same wrapping
  /// row, so it stays above the expanded technical content.
  final String? summary;
  final Color? color;
  final List<Widget> children;
  final bool initiallyExpanded;

  /// Opens the line when this turns true (live progress starting). It never
  /// closes it, so a reader keeps what they expanded.
  final bool expandWhen;
  final bool rail;
  final bool dense;

  /// Marks every direct child of the expanded body as a step: each gets
  /// vertical breathing room and a small dot on the rail. Off by default so
  /// existing callers keep rendering their body untouched.
  final bool steps;

  @override
  State<GenAiDisclosure> createState() => _GenAiDisclosureState();
}

class _GenAiDisclosureState extends State<GenAiDisclosure> {
  late bool _expanded = widget.initiallyExpanded || widget.expandWhen;

  @override
  void didUpdateWidget(covariant GenAiDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expandWhen && !oldWidget.expandWhen) _expanded = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final color = widget.color ?? muted;
    final hasBody = widget.children.isNotEmpty;
    final summary = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme.merge(
          data: IconThemeData(size: 15, color: color),
          child: widget.leading,
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                key: widget.titleKey,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: widget.subtitle == null ? color : theme.colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.subtitle != null || (widget.summary?.isNotEmpty ?? false))
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: color, fontSize: 12),
                      ),
                    if (widget.summary?.isNotEmpty ?? false)
                      SelectableText(
                        widget.summary!,
                        contextMenuBuilder: genAiTextSelectionContextMenu,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (hasBody) ...[
          const SizedBox(width: 6),
          AnimatedRotation(
            turns: _expanded ? .5 : 0,
            duration: const Duration(milliseconds: 160),
            child: GenAiIcon(GenAiGlyph.down, size: 13, color: muted),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            button: hasBody,
            expanded: hasBody ? _expanded : null,
            child: InkWell(
              onTap: hasBody ? () => setState(() => _expanded = !_expanded) : null,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: summary,
                ),
              ),
            ),
          ),
        ),
        if (_expanded && hasBody)
          Container(
            // Reference .activity-body: 8px above, 16px below, 7px from the
            // rail, then 20px of padding before the step text.
            margin: const EdgeInsetsDirectional.only(start: 7, top: 8, bottom: 16),
            padding: EdgeInsetsDirectional.only(
              // The -24px dot is measured from the step content edge, so the
              // 20px gutter puts it on the rail itself.
              start: widget.steps ? 20 : 18,
              top: 2,
              bottom: widget.steps ? 4 : 2,
            ),
            decoration: widget.rail
                ? BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: widget.steps
                  ? [
                      for (final child in widget.children)
                        _step(theme.colorScheme.outlineVariant, child),
                    ]
                  : widget.children,
            ),
          ),
      ],
    );
  }

  /// Reference `.step`: 7px above and below, with a 6px dot at (-24, 16) of
  /// the step box. The dot paints over the body's left padding, so the stack
  /// must not clip (Stack clips by default).
  Widget _step(Color color, Widget child) => Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: child,
          ),
          Positioned(
            left: -24,
            top: 16,
            width: 6,
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
        ],
      );
}
