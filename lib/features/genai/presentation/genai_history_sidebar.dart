import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/genai_platform_contract.dart';
import 'genai_copy.dart';
import 'genai_history_controller.dart';
import 'genai_hover_region.dart';
import 'genai_icons.dart';
import 'genai_theme.dart';

/// One navigation surface for the wide sidebar and the compact drawer:
/// brand and account, the two primary destinations, then searchable history
/// grouped by day. Row actions appear on hover and stay visible on touch.
class GenAiHistorySidebar extends StatelessWidget {
  const GenAiHistorySidebar({
    super.key,
    required this.history,
    required this.connected,
    required this.sending,
    required this.activeId,
    required this.imagesActive,
    required this.accountMenu,
    required this.onNewChat,
    required this.onImages,
    required this.onOpen,
    required this.menuBuilder,
    this.onExit,
    required this.onSearch,
    this.shortcutLabel,
    this.touch = false,
    this.width = 232,
  });

  final GenAiHistoryController history;
  final bool connected;
  final bool sending;
  final String activeId;
  final bool imagesActive;
  final Widget accountMenu;
  final VoidCallback onNewChat;
  final VoidCallback? onImages;
  final ValueChanged<GenAiConversationSummary> onOpen;
  final Widget Function(GenAiConversationSummary conversation) menuBuilder;
  final VoidCallback? onExit;
  final VoidCallback onSearch;

  /// Shown on hover beside 新对话; null hides it (touch layouts).
  final String? shortcutLabel;
  final bool touch;

  /// The sidebar's own width. The workspace supplies the responsive value; the
  /// default matches the design draft's 232 px desktop rail.
  final double width;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: history,
        builder: (context, _) => _sidebar(context),
      );

  Widget _sidebar(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final theme = Theme.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: BorderDirectional(end: BorderSide(color: palette.line.withValues(alpha: .7))),
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          // Draft rail: 18 top, 14 sides, 12 bottom.
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, end: 4, bottom: 24),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/icon/icon.png',
                      width: 29,
                      height: 33,
                      fit: BoxFit.contain,
                      semanticLabel: '',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'GenAI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                    accountMenu,
                  ],
                ),
              ),
              _NavButton(
                key: const ValueKey('genai-new-chat-wide'),
                icon: const GenAiIcon(GenAiGlyph.plus),
                label: '新对话',
                shortcut: touch ? null : shortcutLabel,
                onPressed: sending ? null : onNewChat,
              ),
              _NavButton(
                icon: const GenAiIcon(GenAiGlyph.image),
                label: '图片创作',
                selected: imagesActive,
                onPressed: connected && !sending ? onImages : null,
              ),
              // Draft spacing above the history label.
              const SizedBox(height: 28),
              Expanded(child: _historySection(context, palette)),
              if (onExit != null) ...[
                const SizedBox(height: 15),
                _NavButton(
                  icon: const GenAiIcon(GenAiGlyph.back),
                  label: '返回 TechPie',
                  muted: true,
                  onPressed: onExit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _historySection(BuildContext context, GenAiPalette palette) {
    final caption = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.muted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        );
    if (!connected) {
      return Center(child: Text('未连接 GenAI', style: caption));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, end: 2, bottom: 4),
          child: Row(
            children: [
              Expanded(child: Text('对话', style: caption)),
              IconButton(
                icon: const GenAiIcon(GenAiGlyph.search, size: 18),
                color: palette.muted,
                tooltip: '搜索对话',
                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                onPressed: onSearch,
              ),
              if (history.loading)
                const SizedBox.square(
                  dimension: 36,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const GenAiIcon(GenAiGlyph.refresh, size: 18),
                  color: palette.muted,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  tooltip: '刷新历史',
                  onPressed: () => unawaited(history.load()),
                ),
            ],
          ),
        ),
        if (history.failure case final failure?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(genAiFailureText(failure), style: caption?.copyWith(height: 1.6)),
                TextButton(
                  onPressed: () => unawaited(history.load()),
                  child: const Text('重试加载历史'),
                ),
              ],
            ),
          ),
        Expanded(child: _historyList(context, palette, caption)),
      ],
    );
  }

  Widget _historyList(BuildContext context, GenAiPalette palette, TextStyle? caption) {
    final conversations = history.conversations;
    if (history.loading && conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (conversations.isEmpty) {
      if (history.failure != null) return const SizedBox.shrink();
      return Center(
        child: Text(history.query.isNotEmpty ? '未找到相关对话' : '暂无历史对话', style: caption),
      );
    }
    final rows = <Object>[];
    String? group;
    for (final item in conversations) {
      final label = _dayGroup(item.time);
      if (label != group) rows.add(group = label);
      rows.add(item);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: rows.length + (history.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= rows.length) {
          return Center(
            child: TextButton(
              onPressed: history.loading ? null : () => unawaited(history.load(more: true)),
              child: const Text('加载更多', style: TextStyle(fontSize: 12)),
            ),
          );
        }
        final row = rows[index];
        if (row is String) {
          // Draft group caption: 16 px above, 12 px sides, 7 px below, 11 px type.
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 16, 12, 7),
            child: Text(row, style: caption?.copyWith(fontSize: 11)),
          );
        }
        return _historyRow(context, palette, row as GenAiConversationSummary);
      },
    );
  }

  Widget _historyRow(BuildContext context, GenAiPalette palette, GenAiConversationSummary item) {
    final active = item.id == activeId;
    final title = item.title.isEmpty ? '未命名对话' : item.title;
    // Draft row: a 40 px, 8 px-radius plate inset 14 px by the rail padding,
    // with a 2 px gap before the next plate. Active and hovered both use the
    // palette hover wash.
    return GenAiHoverRegion(
      always: touch,
      builder: (context, revealed) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          key: ValueKey('genai-history-row-${item.id}'),
          color: active ? palette.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            hoverColor: palette.hover,
            onTap: sending ? null : () => onOpen(item),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: item.time.isEmpty ? title : '$title\n${genAiHistoryTime(item.time)}',
                      waitDuration: const Duration(seconds: 1),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: palette.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Draft row gap between the title and the 28 px menu target.
                  const SizedBox(width: 2),
                  // The 28 px target is a square centered in the 40 px row and
                  // inset 6 px from the row's clipped end, so its hover plate
                  // reads as its own control instead of touching the selected
                  // row's rounded corner.
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButtonTheme(
                        // Draft row menu: its own 6 px-radius square hover wash
                        // inside the row, never the circular default. The wash
                        // is explicit so it stays distinct from the selected
                        // row's plate as well as an unselected one.
                        data: IconButtonThemeData(
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            hoverColor: palette.muted.withValues(alpha: .12),
                          ),
                        ),
                        child: GenAiReveal(visible: revealed, child: menuBuilder(item)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Day buckets in the device's local time; unparseable server times fall
  /// into the oldest bucket instead of disappearing.
  static String _dayGroup(String value) {
    final time = DateTime.tryParse(value)?.toLocal();
    if (time == null) return '更早';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final age = today.difference(day).inDays;
    if (age <= 0) return '今天';
    if (age == 1) return '昨天';
    if (age < 7) return '过去 7 天';
    if (age < 30) return '过去 30 天';
    return '更早';
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.shortcut,
    this.selected = false,
    this.muted = false,
  });

  final Widget icon;
  final String label;
  final String? shortcut;
  final bool selected;
  final bool muted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final foreground = selected
        ? palette.accent
        : muted
            ? palette.muted
            : palette.text;
    return GenAiHoverRegion(
      builder: (context, revealed) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          alignment: AlignmentDirectional.centerStart,
          minimumSize: const Size.fromHeight(44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          backgroundColor: selected ? palette.accentSoft : null,
          foregroundColor: foreground,
          textStyle: TextStyle(fontSize: muted ? 12 : 14, fontWeight: FontWeight.w500),
        ),
        child: Row(
          children: [
            IconTheme.merge(data: const IconThemeData(size: 18), child: icon),
            const SizedBox(width: 10),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (shortcut != null)
              GenAiReveal(
                visible: revealed,
                child: Text(shortcut!, style: TextStyle(fontSize: 11, color: palette.muted)),
              ),
          ],
        ),
      ),
    );
  }
}
