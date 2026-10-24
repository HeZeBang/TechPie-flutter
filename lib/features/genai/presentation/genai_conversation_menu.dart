import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/adaptive_feedback.dart';
import '../application/genai_transcript_export.dart';
import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_platform_contract.dart';

/// The same compact actions in the wide sidebar and mobile history page.
class GenAiConversationMenu extends StatefulWidget {
  const GenAiConversationMenu({
    super.key,
    required this.workspace,
    required this.conversation,
    required this.onChanged,
    required this.onDelete,
    this.enabled = true,
  });
  final GenAiWorkspaceController workspace;
  final GenAiConversationSummary conversation;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  State<GenAiConversationMenu> createState() => _GenAiConversationMenuState();
}

class _GenAiConversationMenuState extends State<GenAiConversationMenu> {
  bool _busy = false;
  GenAiCancellation? _operation;

  Future<void> _perform(String action) async {
    if (_busy) return;
    if (action == 'delete') {
      widget.onDelete();
      return;
    }
    final workspace = widget.workspace;
    final conversation = widget.conversation;
    final revision = workspace.conversationRevision;
    final accountRevision = workspace.sessions.revision;
    final accountScope = workspace.accountScope;
    bool current() =>
        mounted &&
        identical(widget.workspace, workspace) &&
        widget.conversation.id == conversation.id &&
        workspace.conversationRevision == revision &&
        workspace.sessions.revision == accountRevision &&
        workspace.accountScope == accountScope;
    final cancellation = GenAiCancellation();
    _operation = cancellation;
    setState(() => _busy = true);
    try {
      if (action == 'rename') {
        final name = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AnimatedBuilder(
            animation: workspace,
            builder: (_, __) => current()
                ? _RenameDialog(title: conversation.title)
                : AlertDialog(
                    title: const Text('对话或账号已切换'),
                    content: const Text('请重新打开重命名。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
          ),
        );
        if (name == null || !current()) return;
        await workspace.renameConversation(conversation.id, name);
        if (current()) widget.onChanged();
      } else {
        final archive = await workspace.conversationForExport(
          conversation.id,
          cancellation,
        );
        if (!mounted || !current()) return;
        final markdown = exportGenAiTranscript(archive);
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AnimatedBuilder(
            animation: workspace,
            builder: (_, __) => AlertDialog(
              title: const Text('导出对话'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: SelectableText(
                    current() ? markdown : '对话或账号已切换，请重新打开导出。',
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
                FilledButton.icon(
                  onPressed: !current()
                      ? null
                      : () async {
                          if (!current()) return;
                          try {
                            await Clipboard.setData(
                              ClipboardData(text: markdown),
                            );
                            if (dialogContext.mounted && current()) {
                              showAdaptiveFeedback(
                                context: dialogContext,
                                message: '已复制 Markdown 对话',
                              );
                            }
                          } catch (_) {
                            if (dialogContext.mounted) {
                              showAdaptiveFeedback(
                                context: dialogContext,
                                message: '无法复制，请手动选择文字',
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制 Markdown'),
                ),
              ],
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && current()) {
        showAdaptiveFeedback(
          context: context,
          message: action == 'rename' ? '重命名失败，请重试' : '导出失败，请重试',
        );
      }
    } finally {
      cancellation.cancel();
      if (identical(_operation, cancellation)) _operation = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _operation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: '对话操作',
        enabled: widget.enabled && !_busy,
        icon: const Icon(Icons.more_horiz, size: 20),
        onSelected: (value) => unawaited(_perform(value)),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('重命名')),
          PopupMenuItem(value: 'export', child: Text('导出对话')),
          PopupMenuItem(value: 'delete', child: Text('删除对话')),
        ],
      );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title});
  final String title;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.title);
  bool get _valid =>
      _name.text.trim().isNotEmpty && _name.text.trim().length <= 120;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_valid) Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: _name,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: '对话名称',
            helperText: '仅修改本机名称，原始消息保留。',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _valid ? _save : null,
            child: const Text('保存'),
          ),
        ],
      );
}
