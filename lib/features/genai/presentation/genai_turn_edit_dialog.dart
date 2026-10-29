import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/genai_failure.dart';
import 'genai_copy.dart';

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
  });

  final String prompt;
  final String action;
  final int removedTurns;
  final bool hasExternalActions;
  final bool hasComposerDraft;
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
      if (mounted && !_committed) Navigator.pop(context);
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
    final editing = widget.action == 'edit';
    final title = editing
        ? '编辑并重新发送'
        : widget.action == 'revert'
            ? '回退到此处'
            : '删除此轮及后续';
    return PopScope(
      canPop: !_submitting,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
        },
        child: AlertDialog(
          scrollable: true,
          title: Text(title),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (editing) ...[
                  TextField(
                    controller: _text,
                    readOnly: _submitting,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('将永久删除 ${widget.removedTurns} 轮对话及其工具记录，所有设备同步生效。'),
                if (editing) const Text('原附件会保留用于重新发送。'),
                if (widget.hasComposerDraft) const Text('输入框中的草稿和附件保持不变，不会随本次编辑发送。'),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (widget.hasExternalActions) ...[
                  const SizedBox(height: 8),
                  const Text('删除记录不会撤销已提交的预约或图片任务。'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _submitting || editing && _text.text.trim().isEmpty ? null : _submit,
              child: Text(
                _submitting
                    ? '处理中…'
                    : editing
                        ? '重新发送'
                        : '确认',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
