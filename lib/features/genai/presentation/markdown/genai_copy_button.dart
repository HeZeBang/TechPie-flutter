import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../widgets/adaptive_feedback.dart';

/// Reports success only after the platform accepts the clipboard write.
class GenAiCopyButton extends StatefulWidget {
  const GenAiCopyButton({
    super.key,
    required this.text,
    required this.tooltip,
    this.showLabel = false,
  });

  final String text;
  final String tooltip;
  final bool showLabel;

  @override
  State<GenAiCopyButton> createState() => _GenAiCopyButtonState();
}

class _GenAiCopyButtonState extends State<GenAiCopyButton> {
  Timer? _reset;
  bool _copied = false;
  bool _pending = false;

  @override
  void didUpdateWidget(GenAiCopyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _reset?.cancel();
      _copied = false;
    }
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final text = widget.text;
    setState(() => _pending = true);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted || text != widget.text) return;
      _reset?.cancel();
      setState(() => _copied = true);
      _reset = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    } catch (_) {
      if (mounted && text == widget.text) {
        setState(() => _copied = false);
        showAdaptiveFeedback(context: context, message: '无法复制，请手动选择文字');
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = Icon(
      _copied ? Icons.check_rounded : Icons.copy_rounded,
      size: 16,
    );
    final color = _copied
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final tooltip = _copied ? '已复制' : widget.tooltip;
    if (widget.showLabel) {
      return TextButton.icon(
        onPressed: _pending ? null : _copy,
        icon: icon,
        label: Text(_copied ? '已复制' : '复制', semanticsLabel: tooltip),
        style: TextButton.styleFrom(foregroundColor: color),
      );
    }
    return IconButton(
      tooltip: tooltip,
      onPressed: _pending ? null : _copy,
      icon: icon,
      color: color,
    );
  }
}
