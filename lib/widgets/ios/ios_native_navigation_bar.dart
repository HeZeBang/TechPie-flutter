import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

class IosNativeNavigationBar extends StatelessWidget implements PreferredSizeWidget {
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
    if (largeTitleMode) {
      return hasSubtitle ? 112.0 : 96.0;
    }
    return hasSubtitle ? 56.0 : 44.0;
  }

  /// Scrollable counterpart: Cupertino owns the title transition, while the
  /// toolbar keeps using the native button and menu adapters below.
  Widget buildSliver(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    return CupertinoSliverNavigationBar(
      automaticallyImplyLeading: false,
      automaticallyImplyTitle: false,
      alwaysShowMiddle: false,
      // Platform views must stay in one toolbar, not be copied into a Hero.
      transitionBetweenRoutes: false,
      border: null,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.9),
      largeTitle: Text(title, style: TextStyle(color: scheme.onSurface)),
      middle: hasSubtitle
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            )
          : Text(title, style: TextStyle(color: scheme.onSurface)),
      leading: leadingItems.any((item) => !item.hidden) ? _actions(context, leadingItems) : null,
      trailing: trailingItems.any((item) => !item.hidden) ? _actions(context, trailingItems) : null,
      bottom: hasSubtitle
          ? PreferredSize(
              preferredSize: const Size.fromHeight(26),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isIos()) return AppBar(title: Text(title));
    final scheme = Theme.of(context).colorScheme;
    final titleWidget = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: largeTitleMode ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: largeTitleMode ? 34 : 17,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: largeTitleMode ? 15 : 12,
              height: 1.15,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: _barHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              SizedBox(
                height: largeTitleMode ? 44 : _barHeight,
                child: Row(
                  children: [
                    _actions(context, leadingItems),
                    Expanded(child: largeTitleMode ? const SizedBox() : titleWidget),
                    _actions(context, trailingItems),
                  ],
                ),
              ),
              if (largeTitleMode)
                Expanded(
                  child: Align(alignment: AlignmentDirectional.centerStart, child: titleWidget),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, List<IosNativeNavigationBarItem> items) {
    final visible = items.where((item) => !item.hidden).toList();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.4,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                SizedBox(
                  width: visible[i].placementGroup == visible[i - 1].placementGroup ? 4 : 12,
                ),
              _action(context, visible[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context, IosNativeNavigationBarItem item) {
    final tint = item.role == IosNativeNavigationBarItemRole.destructive
        ? CupertinoColors.systemRed.resolveFrom(context)
        : Theme.of(context).colorScheme.primary;
    final label = item.accessibilityLabel ?? item.title ?? item.id;
    if (item.menuItems.isNotEmpty) {
      // Inline UIMenu sections map to dividers. Named submenus retain their
      // hierarchy in the label because CNPopupMenuButton has a flat API.
      final entries = <CNPopupMenuEntry>[];
      final values = <String?>[];
      void addItems(List<IosNativeNavigationBarMenuItem> items, String prefix) {
        for (final entry in items) {
          if (entry.children.isNotEmpty) {
            if (entries.isNotEmpty && entries.last is! CNPopupMenuDivider) {
              entries.add(const CNPopupMenuDivider());
              values.add(null);
            }
            addItems(
              entry.children,
              entry.displayInline || entry.title.isEmpty ? prefix : '$prefix${entry.title} › ',
            );
          } else {
            entries.add(
              CNPopupMenuItem(
                label: '$prefix${entry.title}',
                icon: entry.sfSymbol == null ? null : CNSymbol(entry.sfSymbol!),
                checked: entry.checked,
                isDestructive: entry.destructive,
              ),
            );
            values.add(entry.value);
          }
        }
      }

      addItems(item.menuItems, '');
      void select(int index) {
        if (item.enabled && index >= 0 && index < values.length && values[index] != null) {
          onMenuSelected?.call(item.id, values[index]!);
        }
      }

      final menu = item.sfSymbol != null
          ? CNPopupMenuButton.icon(
              buttonIcon: CNSymbol(item.sfSymbol!),
              semanticLabel: label,
              items: entries,
              onSelected: select,
              tint: tint,
            )
          : CNPopupMenuButton(
              buttonLabel: item.title ?? label,
              semanticLabel: label,
              items: entries,
              onSelected: select,
              height: 44,
              shrinkWrap: true,
              buttonStyle: CNButtonStyle.glass,
              tint: tint,
            );
      return IgnorePointer(
        ignoring: !item.enabled,
        child: Opacity(opacity: item.enabled ? 1 : 0.4, child: menu),
      );
    }
    final config = CNButtonConfig(
      style: item.role == IosNativeNavigationBarItemRole.done
          ? CNButtonStyle.prominentGlass
          : CNButtonStyle.glass,
      minHeight: 44,
      shrinkWrap: true,
      glassEffectUnionId: item.placementGroup,
    );
    final callback = item.enabled ? () => onItemPressed?.call(item.id) : null;
    if (item.title != null && item.title!.isNotEmpty) {
      return CNButton(
        label: item.title!,
        icon: item.sfSymbol == null ? null : CNSymbol(item.sfSymbol!),
        semanticLabel: label,
        onPressed: callback,
        enabled: item.enabled,
        tint: tint,
        config: config,
      );
    }
    return CNButton.icon(
      icon: CNSymbol(item.sfSymbol ?? 'ellipsis'),
      semanticLabel: label,
      onPressed: callback,
      enabled: item.enabled,
      tint: tint,
      config: CNButtonConfig(
        style: config.style,
        width: 44,
        minHeight: 44,
        glassEffectUnionId: item.placementGroup,
      ),
    );
  }
}
