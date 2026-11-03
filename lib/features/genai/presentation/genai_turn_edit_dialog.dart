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
    this.hasComposerDraft = false,
    this.hasAttachments = false,
  });

  final String prompt;
  final String action;
  final int removedTurns;
  final bool hasExternalActions;
  final bool hasComposerDraft;

  /// Whether the edited turn carries attachments that resend with it. The
  /// workspace owner supplies the real value from the turn's media.
  final bool hasAttachments;
  final Future<void> Function(String, VoidCallback) onSubmit;

  @override
  State<GenAiTurnEditDialog> createState() => _GenAiTurnEditDialogState();
}

class _GenAiTurnEditDialogState extends State<GenAiTurnEditDialog> {
  late final _text = TextEditingController(text: widget.prompt);

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
          Navigator.pop(context);
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
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final editing = widget.action == 'edit';
    final title = editing
        ? '编辑消息'
        : widget.action == 'revert'
            ? '回退到此处'
            : '删除此轮及后续';
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
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
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
                        if (editing) ...[
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 120),
                            child: TextField(
                              controller: _text,
                              readOnly: _submitting,
                              autofocus: true,
                              minLines: 4,
                              maxLines: 8,
                              style: TextStyle(height: 1.5, color: palette.text),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: palette.soft,
                                contentPadding: const EdgeInsets.all(12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide: BorderSide(color: palette.line),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide: BorderSide(color: palette.line),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide: BorderSide(color: palette.accent),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
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
                        onPressed:
                            _submitting || editing && _text.text.trim().isEmpty ? null : _submit,
                        child: Text(
                          _submitting
                              ? '处理中…'
                              : editing
                                  ? '保存并重发'
                                  : '确认',
                        ),
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
  /// instead of inventing a removal. [GenAiTurnEditDialog.hasComposerDraft]
  /// stays as an input for callers, but no longer lengthens the warning.
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
