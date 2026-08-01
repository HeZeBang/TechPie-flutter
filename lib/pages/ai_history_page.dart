import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ai_chat.dart';
import '../services/ai_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';

/// Lists past conversations. Tap to open (returns the id), swipe/trailing to
/// delete, rename via the overflow menu. A "新对话" action in the app bar
/// creates a fresh thread.
class AiHistoryPage extends StatelessWidget {
  const AiHistoryPage({super.key, required this.aiService});

  final AiService aiService;

  @override
  Widget build(BuildContext context) {
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: '历史会话',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Chat',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回对话',
                  placementGroup: 'leading-main',
                ),
              ],
              trailingItems: const [
                IosNativeNavigationBarItem(
                  id: 'new',
                  title: '新对话',
                  sfSymbol: 'square.and.pencil',
                  placementGroup: 'trailing-main',
                ),
              ],
              onItemPressed: (id) {
                switch (id) {
                  case 'back':
                    unawaited(Navigator.maybePop(context));
                  case 'new':
                    final conv = aiService.newConversation();
                    Navigator.of(context).pop<String>(conv.id);
                }
              },
            )
          : BlurredAppBar(
              title: const Text('历史会话'),
              actions: [
                IconButton(
                  tooltip: '新对话',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: () {
                    final conv = aiService.newConversation();
                    Navigator.of(context).pop<String>(conv.id);
                  },
                ),
              ],
            ),
      body: ListenableBuilder(
        listenable: aiService,
        builder: (context, _) {
          final conversations = aiService.conversations;
          if (conversations.isEmpty) {
            return _empty(context, theme, colorScheme);
          }
          final currentId = aiService.currentConversation?.id;
          return ListView.separated(
            padding: EdgeInsets.only(
              top: useIosChrome || useLegacyIosChrome
                  ? 8
                  : adaptiveTopBarHeight() +
                        MediaQuery.viewPaddingOf(context).top +
                        8,
              bottom: 16,
            ),
            itemCount: conversations.length,
            separatorBuilder: (context, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final c = conversations[i];
              final isCurrent = c.id == currentId;
              return Dismissible(
                key: ValueKey(c.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: colorScheme.error,
                  child: Icon(Icons.delete, color: colorScheme.onError),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('删除该会话？'),
                      content: Text(c.title),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (_) async {
                  await aiService.deleteConversation(c.id);
                  if (context.mounted) {
                    showAdaptiveFeedback(
                      message: '已删除',
                      style: AdaptiveFeedbackStyle.success,
                    );
                  }
                },
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHigh,
                    foregroundColor: isCurrent
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                  title: Text(
                    c.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: isCurrent ? FontWeight.bold : null,
                    ),
                  ),
                  subtitle: Text(
                    _subtitle(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          unawaited(_rename(context, c));
                        case 'delete':
                          unawaited(_deleteWithConfirm(context, c));
                      }
                    },
                  ),
                  onTap: () => Navigator.of(context).pop<String>(c.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _subtitle(AiThread c) {
    final count = c.messages.length;
    final date = '${c.updatedAt.month}/${c.updatedAt.day}';
    return '$date · $count 条消息';
  }

  Widget _empty(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('暂无历史会话', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, AiThread c) async {
    final controller = TextEditingController(text: c.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty) {
      await aiService.renameConversation(c.id, result);
    }
  }

  Future<void> _deleteWithConfirm(BuildContext context, AiThread c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除该会话？'),
        content: Text(c.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await aiService.deleteConversation(c.id);
      if (context.mounted) {
        showAdaptiveFeedback(
          message: '已删除',
          style: AdaptiveFeedbackStyle.success,
        );
      }
    }
  }
}
