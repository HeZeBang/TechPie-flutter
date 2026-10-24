import 'dart:async';

import 'package:flutter/material.dart';

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
    required this.username,
    required this.demo,
    required this.actions,
    required this.onOpen,
    required this.menuBuilder,
  });

  final GenAiHistoryController history;
  final bool connected;
  final bool sending;
  final String activeId;
  final String username;
  final bool demo;
  final Widget actions;
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
      width: 248,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: border)),
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
                  Icon(Icons.auto_awesome_outlined, color: accent, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'TechPie',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 2),
              child: Text(
                '校园智能助手',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  letterSpacing: .3,
                ),
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
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      tooltip: '刷新历史',
                      onPressed: connected && !history.loading
                          ? () => unawaited(history.load())
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _sidebarHistoryList(context),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: border),
            const SizedBox(height: 12),
            _sidebarUserFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _sidebarHistoryList(BuildContext context) {
    final theme = Theme.of(context);
    final conversations = history.conversations;
    final accent = theme.colorScheme.primary;
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
            constraints: const BoxConstraints(minHeight: 40),
            child: TextField(
              controller: history.searchController,
              style: const TextStyle(fontSize: 12),
              onChanged: history.searchChanged,
              decoration: InputDecoration(
                hintText: '搜索历史对话',
                hintStyle: TextStyle(fontSize: 12, color: muted),
                prefixIcon: Icon(Icons.search, size: 16, color: muted),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: .5),
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
                      itemCount:
                          conversations.length + (history.hasMore ? 1 : 0),
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
                                ? accent.withValues(alpha: .12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: sending || isActive
                                  ? null
                                  : () => onOpen(item),
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
                                      color: isActive ? accent : muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            item.title.isEmpty
                                                ? '未命名对话'
                                                : item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: isActive
                                                  ? accent
                                                  : theme.colorScheme.onSurface,
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

  Widget _sidebarUserFooter(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = colors.primary;
    final muted = colors.onSurfaceVariant;
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: accent.withValues(alpha: .1),
          child: Icon(Icons.person_outline, size: 19, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connected ? (demo ? '预览同学' : username) : '尚未连接',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                demo ? '本地演示账户' : '校园 GenAI',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
