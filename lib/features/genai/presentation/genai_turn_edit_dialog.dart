import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/genai_failure.dart';
import 'genai_copy.dart';
import 'genai_icons.dart';
import 'genai_theme.dart';

/// Keeps replacement text available until the server edit succeeds.
class GenAiTurnEditDialog extends StatefulWidget {
  const GenAiTurnEditDialog({
    super.key,
    required this.prompt,
    required this.action,
    required this.removedTurns,
    required this.hasExternalActions,
    required this.onSubmit,
    this.controller,
    this.onClose,
    this.hasAttachments = false,
  });

  final String prompt;
  final String action;
  final int removedTurns;
  final bool hasExternalActions;
  final TextEditingController? controller;
  final VoidCallback? onClose;

  /// Whether the edited turn carries attachments that resend with it. The
  /// workspace owner supplies the real value from the turn's media.
  final bool hasAttachments;
  final Future<void> Function(String, VoidCallback) onSubmit;

  @override
  State<GenAiTurnEditDialog> createState() => _GenAiTurnEditDialogState();
}

class _GenAiTurnEditDialogState extends State<GenAiTurnEditDialog>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.action == 'edit';
  late final _text = widget.controller ?? TextEditingController(text: widget.prompt);

  void _close() {
    if (widget.onClose case final close?) {
      close();
    } else {
      Navigator.pop(context);
    }
  }

  bool _submitting = false;
  bool _committed = false;
  String? _error;

  Future<void> _submit() async {
    final editing = widget.action == 'edit';
    if (_submitting ||
        editing && (_text.text.trim().isEmpty || !_text.value.composing.isCollapsed)) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(editing ? _text.text : '', () {
        if (mounted) {
          _committed = true;
          _close();
        }
      });
      if (mounted && !_committed) {
        throw const GenAiFailure(GenAiFailureKind.historyChanged);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error is GenAiFailure ? genAiFailureText(error) : '操作失败，请重试';
        });
      }
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = GenAiPalette.of(context);
    final editing = widget.action == 'edit';
    if (editing) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_submitting) _close();
          },
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('genai-inline-edit'),
              controller: _text,
              autofocus: true,
              readOnly: _submitting,
              minLines: 1,
              maxLines: 8,
              decoration: const InputDecoration.collapsed(hintText: '编辑消息'),
              style: TextStyle(color: palette.text, height: 1.6),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              _warning(),
              key: const ValueKey('genai-turn-dialog-warning'),
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              children: [
                TextButton(onPressed: _submitting ? null : _close, child: const Text('取消')),
                FilledButton(
                  onPressed: _submitting || _text.text.trim().isEmpty ? null : _submit,
                  child: Text(_submitting ? '处理中…' : '保存并重发'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final title = widget.action == 'revert' ? '回退到此处' : '删除此轮及后续';
    final width = math.min(500.0, MediaQuery.sizeOf(context).width - 32);
    return PopScope(
      canPop: !_submitting,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
        },
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          child: SizedBox(
            key: const ValueKey('genai-turn-dialog'),
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  key: const ValueKey('genai-turn-dialog-header'),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('genai-turn-dialog-close'),
                        tooltip: '关闭',
                        icon: const GenAiIcon(GenAiGlyph.close),
                        iconSize: 18,
                        color: palette.muted,
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                        onPressed: _submitting ? null : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: palette.line),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('genai-turn-dialog-body'),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _warning(),
                          key: const ValueKey('genai-turn-dialog-warning'),
                          style: TextStyle(fontSize: 13, height: 1.7, color: palette.muted),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  key: const ValueKey('genai-turn-dialog-footer'),
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _submitting ? null : () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 9),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: Text(_submitting ? '处理中…' : '确认'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One short paragraph: what the confirmed action replaces, plus only the
  /// consequences that actually apply. Attachments survive an edit (the
  /// controller copies them onto the replacement turn), so the clause says so
  /// instead of inventing a removal.
  String _warning() {
    final buffer = StringBuffer(
      widget.action == 'edit'
          ? '这条消息及之后的回答将被替换。'
          : '将永久删除 ${widget.removedTurns} 轮对话及其工具记录，所有设备同步生效。',
    );
    if (widget.action == 'edit' && widget.hasAttachments) {
      buffer.write('原附件会保留并随新消息重新发送。');
    }
    if (widget.hasExternalActions) {
      buffer.write('删除记录不会撤销已提交的预约或图片任务。');
    }
    return buffer.toString();
  }
}
