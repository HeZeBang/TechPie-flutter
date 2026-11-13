import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../widgets/adaptive_feedback.dart';
import '../genai_icons.dart';
import '../genai_theme.dart';
import 'genai_code_font.dart';

/// Inline diagram controls. The renderer owns its canvas and fullscreen navigation.
class GenAiRichAnswerFrame extends StatefulWidget {
  const GenAiRichAnswerFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.source,
    required this.sourceLabel,
    required this.preview,
    this.onFullscreen,
    this.fullscreenFromSource = false,
    this.onFit,
    this.error,
  });

  final String title;
  final GenAiGlyph icon;
  final String source;
  final String sourceLabel;
  final WidgetBuilder? preview;
  final VoidCallback? onFullscreen;
  final bool fullscreenFromSource;
  final VoidCallback? onFit;
  final String? error;

  @override
  State<GenAiRichAnswerFrame> createState() => _GenAiRichAnswerFrameState();
}

enum _DiagramAction { fit, source, copy }

class _GenAiRichAnswerFrameState extends State<GenAiRichAnswerFrame> {
  bool _showSource = false;

  Future<void> _menu(BuildContext anchor) async {
    final source = widget.source;
    final result = await genAiShowMenu<_DiagramAction>(
      context: context,
      anchorContext: anchor,
      minWidth: 180,
      semanticLabel: '图表操作',
      items: [
        if (!_showSource && widget.onFit != null)
          const PopupMenuItem(value: _DiagramAction.fit, child: Text('适应窗口')),
        if (widget.preview != null)
          PopupMenuItem(
            value: _DiagramAction.source,
            child: Text(_showSource ? '切换到图表' : '查看${widget.sourceLabel}'),
          ),
        PopupMenuItem(value: _DiagramAction.copy, child: Text('复制${widget.sourceLabel}')),
      ],
    );
    if (!mounted || source != widget.source) return;
    switch (result) {
      case _DiagramAction.fit:
        widget.onFit?.call();
      case _DiagramAction.source:
        setState(() => _showSource = !_showSource);
      case _DiagramAction.copy:
        try {
          await Clipboard.setData(ClipboardData(text: source));
          if (mounted && source == widget.source) {
            showAdaptiveFeedback(context: context, message: '已复制${widget.sourceLabel}');
          }
        } catch (_) {
          if (mounted && source == widget.source) {
            showAdaptiveFeedback(context: context, message: '无法复制，请手动选择文字');
          }
        }
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final preview = widget.preview;
    final error = widget.error;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GenAiContentHeader(
            title: widget.title,
            leading: GenAiIcon(
              widget.icon,
              size: 16,
              color: preview == null ? Theme.of(context).colorScheme.error : palette.accent,
            ),
            actions: [
              if (widget.onFullscreen != null && (!_showSource || widget.fullscreenFromSource))
                IconButton(
                  tooltip: '全屏查看',
                  icon: const GenAiIcon(GenAiGlyph.full, size: 20),
                  onPressed: widget.onFullscreen,
                ),
              Builder(
                builder: (anchor) => IconButton(
                  tooltip: '更多操作',
                  icon: const GenAiIcon(GenAiGlyph.more, size: 20),
                  onPressed: () => _menu(anchor),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_showSource || preview == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                widget.source,
                style: const TextStyle(
                  fontFamily: kGenAiMonospaceFamily,
                  fontFamilyFallback: kGenAiMonospaceFallback,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            )
          else
            preview(context),
        ],
      ),
    );
  }
}
