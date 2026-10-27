import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/app_shell/desktop/desktop_sidebar_tokens.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_copy.dart';
import 'genai_history_controller.dart';

class GenAiHistorySidebar extends StatelessWidget {
  const GenAiHistorySidebar({
    super.key,
    required this.history,
    required this.connected,
    required this.sending,
    required this.activeId,
    required this.actions,
    required this.accountMenu,
    required this.onOpen,
    required this.menuBuilder,
  });

  final GenAiHistoryController history;
  final bool connected;
  final bool sending;
  final String activeId;
  final Widget actions;
  final Widget accountMenu;
  final ValueChanged<GenAiConversationSummary> onOpen;
  final Widget Function(GenAiConversationSummary conversation) menuBuilder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: history,
        builder: (context, _) => _sidebar(context),
      );

  Widget _sidebar(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final border = theme.colorScheme.outlineVariant;
    return Container(
      width: DesktopSidebarTokens.maxExpandedWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: border.withValues(alpha: .5))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, color: accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'GenAI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  accountMenu,
                ],
              ),
            ),
            const SizedBox(height: 20),
            actions,
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Text(
                    '历史对话',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  const Spacer(),
                  if (history.loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      tooltip: '刷新历史',
                      onPressed:
                          connected && !history.loading ? () => unawaited(history.load()) : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _sidebarHistoryList(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarHistoryList(BuildContext context) {
    final theme = Theme.of(context);
    final conversations = history.conversations;
    final selected = theme.colorScheme.onSecondaryContainer;
    final muted = theme.colorScheme.onSurfaceVariant;
    if (!connected) {
      return Center(
        child: Text('未连接 GenAI', style: TextStyle(fontSize: 12, color: muted)),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: TextField(
              controller: history.searchController,
              style: const TextStyle(fontSize: 12),
              onChanged: history.searchChanged,
              decoration: InputDecoration(
                hintText: '搜索历史对话',
                hintStyle: TextStyle(fontSize: 12, color: muted),
                prefixIcon: Icon(Icons.search, size: 16, color: muted),
                prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 44),
                suffixIcon: history.searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          size: 14,
                          semanticLabel: '清除搜索',
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28),
                        onPressed: () {
                          history.searchController.clear();
                          history.searchChanged('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (history.failure case final failure?)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Text(
                  genAiFailureText(failure),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                TextButton(
                  onPressed: () => unawaited(history.load()),
                  child: const Text('重试加载历史'),
                ),
              ],
            ),
          ),
        Expanded(
          child: history.loading && conversations.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : conversations.isEmpty
                  ? history.failure != null
                      ? const SizedBox.shrink()
                      : Center(
                          child: Text(
                            history.query.isNotEmpty ? '未找到相关对话' : '暂无历史对话',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        )
                  : ListView.builder(
                      itemCount: conversations.length + (history.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= conversations.length) {
                          return Center(
                            child: TextButton(
                              onPressed: history.loading
                                  ? null
                                  : () => unawaited(history.load(more: true)),
                              child: const Text(
                                '加载更多',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          );
                        }
                        final item = conversations[index];
                        final isActive = item.id == activeId;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Material(
                            color: isActive
                                ? theme.colorScheme.secondaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(DesktopSidebarTokens.navItemRadius),
                            child: InkWell(
                              borderRadius:
                                  BorderRadius.circular(DesktopSidebarTokens.navItemRadius),
                              onTap: sending || isActive ? null : () => onOpen(item),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isActive
                                          ? Icons.chat_bubble_rounded
                                          : Icons.chat_bubble_outline_rounded,
                                      size: 16,
                                      color: isActive ? selected : muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            item.title.isEmpty ? '未命名对话' : item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight:
                                                  isActive ? FontWeight.w600 : FontWeight.normal,
                                              color:
                                                  isActive ? selected : theme.colorScheme.onSurface,
                                            ),
                                          ),
                                          if (item.time.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              genAiHistoryTime(item.time),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: muted,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    menuBuilder(item),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
