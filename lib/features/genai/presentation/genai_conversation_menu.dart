import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/adaptive_feedback.dart';
import '../application/genai_transcript_export.dart';
import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_icons.dart';
import 'genai_theme.dart';

/// The same compact actions in the wide sidebar and mobile history page.
class GenAiConversationMenu extends StatefulWidget {
  const GenAiConversationMenu({
    super.key,
    required this.workspace,
    required this.conversation,
    required this.onChanged,
    required this.onDelete,
    this.enabled = true,
    this.iconSize = 16,
    this.showSync = false,
    this.workspaceWidth,
  });
  final GenAiWorkspaceController workspace;
  final GenAiConversationSummary conversation;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final bool enabled;
  final double iconSize;

  /// Shows the explicit "检查同步" action. Off by default so the compact
  /// history row keeps only the actions that act on the conversation itself.
  final bool showSync;

  /// The workspace's layout width. Dialogs use it (instead of the window) to
  /// pick the draft's compact <=600 px inset and corner radius. Falls back to
  /// [MediaQuery.sizeOf] when the host does not supply it.
  final double? workspaceWidth;

  @override
  State<GenAiConversationMenu> createState() => _GenAiConversationMenuState();
}

class _GenAiConversationMenuState extends State<GenAiConversationMenu> {
  bool _busy = false;
  GenAiCancellation? _operation;

  /// The draft's compact dialog treatment starts at 600 px of workspace, not
  /// window width, so an embedded workspace keeps its own breakpoint.
  bool get _narrow => (widget.workspaceWidth ?? MediaQuery.sizeOf(context).width) <= 600;

  Future<void> _perform(String action) async {
    if (_busy) return;
    if (action == 'delete') {
      widget.onDelete();
      return;
    }
    final narrow = _narrow;
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
    bool currentAccount() =>
        mounted &&
        identical(widget.workspace, workspace) &&
        workspace.sessions.revision == accountRevision &&
        workspace.accountScope == accountScope;
    final cancellation = GenAiCancellation();
    _operation = cancellation;
    setState(() => _busy = true);
    try {
      if (action == 'rename') {
        final name = await genAiShowDialog<String>(
          context: context,
          builder: (dialogContext) => AnimatedBuilder(
            animation: workspace,
            builder: (_, __) => current()
                ? _RenameDialog(title: conversation.title, narrow: narrow)
                : GenAiDialogFrame(
                    insetPadding: narrow ? const EdgeInsets.all(12) : null,
                    shape: narrow ? _compactDialogShape : null,
                    title: const Text('对话或账号已切换'),
                    content: const Text('请重新打开重命名。'),
                    actions: [
                      TextButton(
                        style: _dialogActionStyle(narrow),
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
          ),
        );
        if (name == null || !current()) return;
        await workspace.renameConversation(conversation.id, name);
        if (mounted && current()) {
          widget.onChanged();
          showAdaptiveFeedback(context: context, message: '名称将在下一条消息时同步');
        }
      } else if (action == 'sync') {
        await workspace.retrySaveConversations();
        if (!currentAccount()) return;
        final failure = workspace.archiveFailure;
        if (!mounted) return;
        showAdaptiveFeedback(
          context: context,
          message: failure == null ? '已检查同步' : '检查同步未完成，请重试',
          style: failure == null ? AdaptiveFeedbackStyle.success : AdaptiveFeedbackStyle.error,
        );
      } else {
        await _showGenAiConversationExport(
          context,
          workspace,
          conversation,
          current: current,
          cancellation: cancellation,
          narrow: narrow,
        );
      }
    } catch (_) {
      final stillCurrent = action == 'sync' ? currentAccount() : current();
      if (mounted && stillCurrent) {
        showAdaptiveFeedback(
          context: context,
          message: action == 'rename'
              ? '重命名失败，请重试'
              : action == 'sync'
                  ? '检查同步失败，请重试'
                  : '导出失败，请重试',
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

  // Draft popover rows: 42 px minimum, 10/8 px padding, 13 px labels,
  // 17 px muted icons and a 10 px gap. The shared route paints each native
  // row's 7 px hover plate through `genAiMenuEntry`.
  Widget _row(GenAiPalette palette, Widget icon, String label, {bool danger = false}) => Row(
        children: [
          IconTheme.merge(
            data: IconThemeData(
              size: 17,
              color: danger ? palette.accent : palette.muted,
            ),
            child: icon,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: danger ? palette.accent : null),
          ),
        ],
      );

  List<PopupMenuEntry<String>> _items(GenAiPalette palette) {
    PopupMenuItem<String> item(String value, Widget icon, String label, {bool danger = false}) =>
        PopupMenuItem<String>(
          value: value,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: _row(palette, icon, label, danger: danger),
        );
    return [
      item('rename', const GenAiIcon(GenAiGlyph.edit), '重命名'),
      item('export', const GenAiIcon(GenAiGlyph.download), '导出对话'),
      if (widget.showSync) item('sync', const GenAiIcon(GenAiGlyph.sync), '检查同步'),
      const PopupMenuDivider(height: 11),
      item('delete', const GenAiIcon(GenAiGlyph.trash), '删除对话', danger: true),
    ];
  }

  /// Every host uses the shared exact-anchor route: 7 px below the button, or
  /// above when it does not fit, with the draft's 220 px minimum width.
  ///
  /// The popover outlives list refreshes and account switches, so the action
  /// re-checks the scope it was opened for before running [_perform].
  Future<void> _openAnchored(
    BuildContext anchorContext,
    List<PopupMenuEntry<String>> items,
  ) async {
    final workspace = widget.workspace;
    final conversation = widget.conversation;
    final revision = workspace.conversationRevision;
    final accountRevision = workspace.sessions.revision;
    final accountScope = workspace.accountScope;
    final value = await genAiShowMenu<String>(
      context: context,
      anchorContext: anchorContext,
      items: items,
      minWidth: 220,
      gap: 7,
      semanticLabel: '对话操作',
    );
    final current = mounted &&
        identical(widget.workspace, workspace) &&
        widget.conversation.id == conversation.id &&
        workspace.conversationRevision == revision &&
        workspace.sessions.revision == accountRevision &&
        workspace.accountScope == accountScope;
    if (current && value != null) await _perform(value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final items = _items(palette);
    final icon = GenAiIcon(GenAiGlyph.more, size: widget.iconSize, color: palette.muted);
    // The compact history row gives the menu a 28 px hover target.
    final buttonStyle = IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.all(4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Builder(
      builder: (anchorContext) => IconButton(
        tooltip: '对话操作',
        icon: icon,
        padding: const EdgeInsets.all(4),
        style: buttonStyle,
        onPressed:
            widget.enabled && !_busy ? () => unawaited(_openAnchored(anchorContext, items)) : null,
      ),
    );
  }
}

/// Draft compact dialog chrome for a workspace at or below 600 px.
const _compactDialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(14)),
);

/// Keeps dialog actions at a 44 px accessible height in the compact layout.
ButtonStyle? _dialogActionStyle(bool narrow) =>
    narrow ? const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(64, 44))) : null;

/// Opens the read-only Markdown export for [conversation].
///
/// The workspace revision, account revision and account scope are captured
/// before the read starts. A late reply is dropped rather than showing (or
/// copying) a transcript that belongs to a conversation or account the user
/// has since left.
Future<void> showGenAiConversationExport(
  BuildContext context,
  GenAiWorkspaceController workspace,
  GenAiConversationSummary conversation, {
  double? workspaceWidth,
}) {
  final revision = workspace.conversationRevision;
  final accountRevision = workspace.sessions.revision;
  final accountScope = workspace.accountScope;
  bool current() =>
      context.mounted &&
      workspace.conversationRevision == revision &&
      workspace.sessions.revision == accountRevision &&
      workspace.accountScope == accountScope;
  final narrow = (workspaceWidth ?? MediaQuery.sizeOf(context).width) <= 600;
  return _showGenAiConversationExport(
    context,
    workspace,
    conversation,
    current: current,
    cancellation: GenAiCancellation(),
    narrow: narrow,
  );
}

/// Shared export implementation. The menu supplies its own row/workspace guard
/// and operation cancellation so a workspace or conversation switch (and a
/// dispose) still invalidates an in-flight export.
Future<void> _showGenAiConversationExport(
  BuildContext context,
  GenAiWorkspaceController workspace,
  GenAiConversationSummary conversation, {
  required bool Function() current,
  required GenAiCancellation cancellation,
  required bool narrow,
}) async {
  try {
    final archive = await workspace.conversationForExport(
      conversation.id,
      cancellation,
    );
    if (!context.mounted || !current()) return;
    final markdown = exportGenAiTranscript(archive);
    await genAiShowDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: workspace,
        builder: (_, __) => GenAiDialogFrame(
          insetPadding: narrow ? const EdgeInsets.all(12) : null,
          shape: narrow ? _compactDialogShape : null,
          title: const Text('导出对话'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: SelectableText(
                current() ? markdown : '对话或账号已切换，请重新打开导出。',
              ),
            ),
          ),
          actions: [
            TextButton(
              style: _dialogActionStyle(narrow),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
            FilledButton.icon(
              style: _dialogActionStyle(narrow),
              onPressed: !current()
                  ? null
                  : () async {
                      if (!current()) return;
                      try {
                        await Clipboard.setData(ClipboardData(text: markdown));
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
              icon: const GenAiIcon(GenAiGlyph.copy),
              label: const Text('复制 Markdown'),
            ),
          ],
        ),
      ),
    );
  } catch (_) {
    if (context.mounted && current()) {
      showAdaptiveFeedback(context: context, message: '导出失败，请重试');
    }
  } finally {
    cancellation.cancel();
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title, required this.narrow});
  final String title;
  final bool narrow;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  static const _maxLength = 120;
  late final _name = TextEditingController(text: widget.title);
  bool get _valid => _name.text.trim().isNotEmpty && _name.text.trim().length <= _maxLength;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_valid) Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final theme = Theme.of(context);
    return Dialog(
      // Draft dialog: min(500, screen - 32) wide with 18 px corners.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      child: ConstrainedBox(
        key: const ValueKey('genai-rename-dialog'),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Draft header: ruled underside, title left, close affordance right.
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '重命名对话',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const GenAiIcon(GenAiGlyph.close, size: 18),
                    color: palette.muted,
                    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: TextField(
                key: const ValueKey('genai-rename-input'),
                controller: _name,
                autofocus: true,
                maxLength: _maxLength,
                textAlignVertical: TextAlignVertical.center,
                strutStyle: StrutStyle(
                  fontSize: widget.narrow ? 16 : 14,
                  height: 1.5,
                  forceStrutHeight: true,
                ),
                style: TextStyle(fontSize: widget.narrow ? 16 : 14, height: 1.5),
                decoration: InputDecoration(
                  // Plain soft field: no floating label, helper or counter.
                  counterText: '',
                  filled: true,
                  fillColor: palette.soft,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: widget.narrow ? 13 : 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: palette.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: palette.line),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: _dialogActionStyle(widget.narrow),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 9),
                  FilledButton(
                    style: _dialogActionStyle(widget.narrow),
                    onPressed: _valid ? _save : null,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
