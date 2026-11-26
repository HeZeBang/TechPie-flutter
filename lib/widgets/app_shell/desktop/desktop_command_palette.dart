import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/theme.dart';
import 'macos_window_drag.dart';

bool _paletteOpen = false;
BuildContext? _activePaletteContext;

/// Whether a [DesktopCommandPalette] dialog is currently open.
bool get isDesktopCommandPaletteOpen => _paletteOpen;

/// Closes the active command palette if open; returns `true` if closed.
bool closeDesktopCommandPaletteIfOpen() {
  final ctx = _activePaletteContext;
  if (!_paletteOpen || ctx == null || !ctx.mounted) return false;
  Navigator.of(ctx).pop();
  return true;
}

/// Entry shown inside [showDesktopCommandPalette].
@immutable
class DesktopCommandItem {
  const DesktopCommandItem({
    required this.id,
    required this.title,
    required this.group,
    required this.icon,
    required this.onExecute,
    this.subtitle = '',
    this.shortcutLabel,
    this.keywords = const <String>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final String group;
  final IconData icon;
  final String? shortcutLabel;
  final List<String> keywords;
  final VoidCallback onExecute;

  bool matches(String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    if (title.toLowerCase().contains(normalizedQuery)) return true;
    if (subtitle.toLowerCase().contains(normalizedQuery)) return true;
    if (group.toLowerCase().contains(normalizedQuery)) return true;
    for (final kw in keywords) {
      if (kw.toLowerCase().contains(normalizedQuery)) return true;
    }
    return false;
  }
}

/// Shows the desktop Raycast/Linear-style command launcher dialog.
///
/// If a palette is already open, toggles it closed instead of stacking a
/// duplicate modal.
Future<void> showDesktopCommandPalette({
  required BuildContext context,
  required List<DesktopCommandItem> items,
}) async {
  if (closeDesktopCommandPaletteIfOpen()) return;
  _paletteOpen = true;
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  try {
    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '关闭快速命令面板',
      barrierColor: Colors.black.withValues(alpha: 0.36),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, __) {
        _activePaletteContext = dialogContext;
        return _DesktopCommandPaletteDialog(items: items);
      },
      transitionBuilder: (context, animation, _, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  } finally {
    _paletteOpen = false;
    _activePaletteContext = null;
  }
}

class _DesktopCommandPaletteDialog extends StatefulWidget {
  const _DesktopCommandPaletteDialog({required this.items});

  final List<DesktopCommandItem> items;

  @override
  State<_DesktopCommandPaletteDialog> createState() =>
      _DesktopCommandPaletteDialogState();
}

class _DesktopCommandPaletteDialogState
    extends State<_DesktopCommandPaletteDialog> {
  final _searchController = TextEditingController();
  final _rowKeys = <int, GlobalKey>{};
  String _query = '';
  int _highlightedIndex = 0;

  List<DesktopCommandItem> get _filteredItems {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items.where((item) => item.matches(q)).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _moveHighlight(int delta, int count) {
    if (count == 0) return;
    setState(() {
      _highlightedIndex = (_highlightedIndex + delta) % count;
      if (_highlightedIndex < 0) _highlightedIndex += count;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowContext = _rowKeys[_highlightedIndex]?.currentContext;
      if (rowContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            rowContext,
            alignment: 0.5,
          ),
        );
      }
    });
  }

  void _executeItem(DesktopCommandItem item) {
    if (!mounted) return;
    Navigator.of(context).pop();
    item.onExecute();
  }

  void _executeHighlighted(List<DesktopCommandItem> filtered) {
    if (filtered.isEmpty) return;
    final index = _highlightedIndex.clamp(0, filtered.length - 1);
    _executeItem(filtered[index]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final filtered = _filteredItems;
    final clampedIndex =
        filtered.isEmpty ? 0 : _highlightedIndex.clamp(0, filtered.length - 1);
    final isMac = isMacOsDesktop();

    // Group matching items while preserving order of first appearance.
    final grouped = <String, List<(int flatIndex, DesktopCommandItem item)>>{};
    for (var i = 0; i < filtered.length; i++) {
      final item = filtered[i];
      grouped.putIfAbsent(item.group, () => []).add((i, item));
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        SingleActivator(
          LogicalKeyboardKey.keyK,
          meta: isMac,
          control: !isMac,
        ): () => Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveHighlight(1, filtered.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveHighlight(-1, filtered.length),
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            _executeHighlighted(filtered),
      },
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TpTokens.space4,
            vertical: TpTokens.space5,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
            child: Material(
              key: const ValueKey('desktop.command-palette'),
              color: colors.surface,
              elevation: 18,
              shadowColor: Colors.black.withValues(alpha: 0.28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TpTokens.radiusL),
                side: BorderSide(
                  color: colors.border == Colors.transparent
                      ? colors.divider
                      : colors.border,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TpTokens.space4,
                      TpTokens.space3,
                      TpTokens.space3,
                      TpTokens.space3,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          TpIcons.search,
                          size: 18,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: TpTokens.space3),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('desktop.command-palette-input'),
                            controller: _searchController,
                            autofocus: true,
                            onChanged: (value) {
                              setState(() {
                                _query = value;
                                _highlightedIndex = 0;
                              });
                            },
                            onSubmitted: (_) => _executeHighlighted(filtered),
                            style: TpTypography.itemTitle(colors).copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: '搜索校园服务、标签页或快捷操作…',
                              hintStyle: TpTypography.itemTitle(colors).copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: colors.textMuted,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: TpTokens.space1,
                              ),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          IconButton(
                            tooltip: '清除搜索',
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _query = '';
                                _highlightedIndex = 0;
                              });
                            },
                            icon: const Icon(TpIcons.close),
                          ),
                        const SizedBox(width: TpTokens.space1),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceSubtle,
                            borderRadius:
                                BorderRadius.circular(TpTokens.radiusXs),
                          ),
                          child: Text(
                            'Esc',
                            style: TpTypography.badge(colors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 0.5, color: colors.divider),
                  Flexible(
                    child: filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(TpTokens.space6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  TpIcons.inbox,
                                  size: TpTokens.iconL,
                                  color: colors.textMuted,
                                ),
                                const SizedBox(height: TpTokens.space2),
                                Text(
                                  '没有找到匹配的命令或服务',
                                  style: TpTypography.itemMeta(colors),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: TpTokens.space2,
                              vertical: TpTokens.space2,
                            ),
                            shrinkWrap: true,
                            children: [
                              for (final entry in grouped.entries) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    TpTokens.space2,
                                    TpTokens.space2,
                                    TpTokens.space2,
                                    TpTokens.space1,
                                  ),
                                  child: Text(
                                    entry.key,
                                    style:
                                        TpTypography.cardMeta(colors).copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                for (final (flatIndex, item) in entry.value)
                                  _CommandRow(
                                    key: _rowKeys.putIfAbsent(
                                      flatIndex,
                                      GlobalKey.new,
                                    ),
                                    item: item,
                                    highlighted: flatIndex == clampedIndex,
                                    onHover: () {
                                      if (_highlightedIndex != flatIndex) {
                                        setState(
                                          () => _highlightedIndex = flatIndex,
                                        );
                                      }
                                    },
                                    onTap: () => _executeItem(item),
                                  ),
                              ],
                            ],
                          ),
                  ),
                  Divider(height: 1, thickness: 0.5, color: colors.divider),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TpTokens.space4,
                      vertical: TpTokens.space2,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '↑↓ 选择  ·  Enter 打开  ·  Esc 关闭',
                          style: TpTypography.cardMeta(colors),
                        ),
                      ],
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
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    super.key,
    required this.item,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final DesktopCommandItem item;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Material(
        color: highlighted ? colors.opaqueBrandContainer : Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TpTokens.space3,
              vertical: 9,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: highlighted ? colors.brandInk : colors.textMuted,
                ),
                const SizedBox(width: TpTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TpTypography.itemTitle(colors).copyWith(
                          fontSize: 14,
                          fontWeight:
                              highlighted ? FontWeight.w600 : FontWeight.w500,
                          color:
                              highlighted ? colors.brandInk : colors.textPrimary,
                        ),
                      ),
                      if (item.subtitle.isNotEmpty)
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TpTypography.cardMeta(colors),
                        ),
                    ],
                  ),
                ),
                if (item.shortcutLabel != null &&
                    item.shortcutLabel!.isNotEmpty) ...[
                  const SizedBox(width: TpTokens.space2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(TpTokens.radiusXs),
                    ),
                    child: Text(
                      item.shortcutLabel!,
                      style: TpTypography.badge(colors.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
