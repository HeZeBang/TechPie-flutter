import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:techpie/utils/platform.dart';

enum IosNativeNavigationBarItemRole { normal, done, destructive }

class IosNativeNavigationBarItem {
  const IosNativeNavigationBarItem({
    required this.id,
    this.title,
    this.sfSymbol,
    this.role = IosNativeNavigationBarItemRole.normal,
    this.enabled = true,
    this.hidden = false,
    this.accessibilityLabel,
    this.placementGroup,
    this.menuItems = const [],
  });

  final String id;
  final String? title;
  final String? sfSymbol;
  final IosNativeNavigationBarItemRole role;
  final bool enabled;
  final bool hidden;
  final String? accessibilityLabel;
  final String? placementGroup;
  final List<IosNativeNavigationBarMenuItem> menuItems;
}

class IosNativeNavigationBarMenuItem {
  const IosNativeNavigationBarMenuItem({
    required this.value,
    required this.title,
    this.sfSymbol,
    this.checked = false,
    this.destructive = false,
    this.displayInline = false,
    this.children = const [],
  });

  final String value;
  final String title;
  final String? sfSymbol;
  final bool checked;
  final bool destructive;
  final bool displayInline;
  final List<IosNativeNavigationBarMenuItem> children;
}

/// A composited Cupertino navigation bar.
///
/// Ordinary navigation chrome stays in Flutter's scene so it participates in
/// [CupertinoPageRoute] as one page instead of becoming a separately animated
/// UIKit platform view. Native platform views remain reserved for content that
/// actually requires a native surface.
class IosNativeNavigationBar extends StatelessWidget
    implements PreferredSizeWidget {
  const IosNativeNavigationBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingItems = const [],
    this.trailingItems = const [],
    this.selectionMode = false,
    this.largeTitleMode = false,
    this.onItemPressed,
    this.onMenuSelected,
  });

  final String title;
  final String? subtitle;
  final List<IosNativeNavigationBarItem> leadingItems;
  final List<IosNativeNavigationBarItem> trailingItems;
  final bool selectionMode;
  final bool largeTitleMode;
  final ValueChanged<String>? onItemPressed;
  final void Function(String id, String value)? onMenuSelected;

  @override
  Size get preferredSize => Size.fromHeight(_barHeight);

  double get _barHeight {
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    if (largeTitleMode) return hasSubtitle ? 104 : 92;
    return hasSubtitle ? 52 : 44;
  }

  @override
  Widget build(BuildContext context) {
    if (!isIos()) return AppBar(title: Text(title));

    final brightness = CupertinoTheme.brightnessOf(context);
    final background = CupertinoDynamicColor.resolve(
      CupertinoColors.systemBackground.withValues(alpha: 0.86),
      context,
    );
    final separator = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
    final visibleLeading = leadingItems.where((item) => !item.hidden).toList();
    final visibleTrailing =
        trailingItems.where((item) => !item.hidden).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              border: Border(bottom: BorderSide(color: separator, width: 0)),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: _barHeight,
                child: Stack(
                  children: [
                    PositionedDirectional(
                      top: 0,
                      start: 4,
                      child: _buildItems(context, visibleLeading),
                    ),
                    PositionedDirectional(
                      top: 0,
                      end: 4,
                      child: _buildItems(context, visibleTrailing),
                    ),
                    if (largeTitleMode)
                      PositionedDirectional(
                        start: 16,
                        end: 16,
                        bottom: subtitle == null ? 8 : 7,
                        child: _LargeTitle(title: title, subtitle: subtitle),
                      )
                    else
                      PositionedDirectional(
                        start: 88,
                        end: 88,
                        top: 0,
                        height: _barHeight,
                        child: _CompactTitle(title: title, subtitle: subtitle),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItems(
    BuildContext context,
    List<IosNativeNavigationBarItem> items,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final item in items) _buildItem(context, item)],
    );
  }

  Widget _buildItem(BuildContext context, IosNativeNavigationBarItem item) {
    final color = item.role == IosNativeNavigationBarItemRole.destructive
        ? CupertinoColors.systemRed
        : CupertinoTheme.of(context).primaryColor;
    final textStyle =
        CupertinoTheme.of(context).textTheme.actionTextStyle.copyWith(
              color: color,
              fontWeight: item.role == IosNativeNavigationBarItemRole.done
                  ? FontWeight.w600
                  : FontWeight.w400,
            );
    final icon = _iconForSymbol(item.sfSymbol);
    final label = item.title;

    return Semantics(
      button: true,
      label: item.accessibilityLabel ?? label,
      enabled: item.enabled,
      child: CupertinoButton(
        minSize: iosMinimumInteractiveDimension,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onPressed: item.enabled
            ? () async {
                if (item.menuItems.isEmpty) {
                  onItemPressed?.call(item.id);
                } else {
                  await _showMenu(context, item.id, item.menuItems);
                }
              }
            : null,
        child: label != null && label.isNotEmpty
            ? Text(label, style: textStyle)
            : Icon(icon, size: 22, color: color),
      ),
    );
  }

  Future<void> _showMenu(
    BuildContext context,
    String itemId,
    List<IosNativeNavigationBarMenuItem> items, {
    String? menuTitle,
  }) async {
    final flattened = <IosNativeNavigationBarMenuItem>[
      for (final item in items)
        if (item.displayInline) ...item.children else item,
    ];

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: menuTitle == null || menuTitle.isEmpty ? null : Text(menuTitle),
        actions: [
          for (final item in flattened)
            CupertinoActionSheetAction(
              isDestructiveAction: item.destructive,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                if (item.children.isNotEmpty) {
                  Future<void>.microtask(() {
                    if (context.mounted) {
                      _showMenu(
                        context,
                        itemId,
                        item.children,
                        menuTitle: item.title,
                      );
                    }
                  });
                } else {
                  onMenuSelected?.call(itemId, item.value);
                }
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: item.checked
                        ? const Icon(CupertinoIcons.check_mark, size: 18)
                        : item.sfSymbol == null
                            ? null
                            : Icon(_iconForSymbol(item.sfSymbol), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.title)),
                  if (item.children.isNotEmpty)
                    const Icon(CupertinoIcons.chevron_forward, size: 16),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }
}

class _CompactTitle extends StatelessWidget {
  const _CompactTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.navTitleTextStyle,
        ),
        if (subtitle case final subtitle? when subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.textStyle.copyWith(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}

class _LargeTitle extends StatelessWidget {
  const _LargeTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.navLargeTitleTextStyle,
        ),
        if (subtitle case final subtitle? when subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.textStyle.copyWith(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontSize: 13,
            ),
          ),
      ],
    );
  }
}

IconData _iconForSymbol(String? symbol) {
  return switch (symbol) {
    'arrow.clockwise' ||
    'arrow.counterclockwise' ||
    'arrow.triangle.2.circlepath' =>
      CupertinoIcons.refresh,
    'arrow.down.circle' ||
    'icloud.and.arrow.down' =>
      CupertinoIcons.cloud_download,
    'arrow.up.circle' || 'icloud.and.arrow.up' => CupertinoIcons.cloud_upload,
    'arrow.uturn.backward' => CupertinoIcons.arrow_uturn_left,
    'calendar.badge.clock' => CupertinoIcons.calendar,
    'checklist' => CupertinoIcons.check_mark_circled,
    'chevron.left' => CupertinoIcons.back,
    'ellipsis' => CupertinoIcons.ellipsis,
    'ellipsis.circle' => CupertinoIcons.ellipsis_circle,
    'icloud.slash' => CupertinoIcons.cloud,
    'key' => CupertinoIcons.lock,
    'link' => CupertinoIcons.link,
    'magnifyingglass' => CupertinoIcons.search,
    'message.badge' => CupertinoIcons.chat_bubble,
    'paperplane.fill' => CupertinoIcons.paperplane_fill,
    'person.crop.circle.badge.plus' => CupertinoIcons.person_add,
    'rectangle.portrait.and.arrow.right' => CupertinoIcons.square_arrow_right,
    'square.and.arrow.down' => CupertinoIcons.square_arrow_down,
    'square.and.arrow.up' => CupertinoIcons.share,
    'trash' => CupertinoIcons.trash,
    _ => CupertinoIcons.circle,
  };
}
