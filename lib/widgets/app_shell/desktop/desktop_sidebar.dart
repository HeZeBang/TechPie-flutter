import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../theme/theme.dart';
import '../../../utils/adaptive_motion.dart';
import '../../../utils/haptics.dart';
import '../../../utils/motion.dart';
import '../../design_system/tp_brand_mark.dart';
import '../app_destination.dart';
import 'desktop_sidebar_item.dart';
import 'desktop_sidebar_tokens.dart';
import 'macos_window_drag.dart';

class DesktopSidebar extends StatelessWidget {
  final List<AppDestination> destinations;
  final int selectedIndex;
  final bool collapsed;
  final bool showToggleButton;
  final Map<int, SidebarBadgeData> badges;
  final ValueChanged<int> onSelected;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onOpenCommandPalette;
  final VoidCallback? onOpenCampusServices;
  final DesktopSidebarAccountSummary? accountSummary;
  final int? accountDestinationIndex;
  final VoidCallback? onOpenAccount;

  const DesktopSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.collapsed,
    this.showToggleButton = true,
    this.badges = const <int, SidebarBadgeData>{},
    required this.onSelected,
    required this.onToggleCollapsed,
    this.onOpenCommandPalette,
    this.onOpenCampusServices,
    this.accountSummary,
    this.accountDestinationIndex,
    this.onOpenAccount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final horizontalPadding = collapsed
        ? DesktopSidebarTokens.collapsedHorizontalPadding
        : DesktopSidebarTokens.expandedHorizontalPadding;
    final itemSpacing = DesktopSidebarTokens.navItemSpacing;
    final navEntries = <_SidebarNavEntry>[
      for (var index = 0; index < destinations.length; index++)
        if (index != accountDestinationIndex)
          _SidebarNavEntry(index: index, destination: destinations[index]),
    ];
    final showAccountFooter =
        accountSummary != null || accountDestinationIndex != null;
    final resolvedSummary = accountSummary ??
        const DesktopSidebarAccountSummary(
          displayName: '我的',
          avatarText: '',
          isLoggedIn: false,
        );
    final accountSelected = accountDestinationIndex != null &&
        selectedIndex == accountDestinationIndex;

    return ColoredBox(
      color: colors.surface,
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SidebarDragHeader(
              horizontalPadding: horizontalPadding,
              collapsed: collapsed,
              showToggleButton: showToggleButton,
              onToggleCollapsed: onToggleCollapsed,
            ),
            if (onOpenCommandPalette != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  TpTokens.space2,
                ),
                child: _SidebarCommandTrigger(
                  collapsed: collapsed,
                  onTap: onOpenCommandPalette!,
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  DesktopSidebarTokens.navTopPadding,
                  horizontalPadding,
                  DesktopSidebarTokens.navBottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SlidingSidebarNavList(
                              entries: navEntries,
                              selectedIndex: selectedIndex,
                              collapsed: collapsed,
                              itemSpacing: itemSpacing,
                              badges: badges,
                              onSelected: (index) {
                                unawaited(AppHaptics.play(AppHaptics.tabSelect));
                                onSelected(index);
                              },
                            ),
                            if (onOpenCampusServices != null) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: TpTokens.space1 + 2,
                                ),
                                child: Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: colors.divider,
                                ),
                              ),
                              _SidebarUtilityButton(
                                buttonKey: const ValueKey(
                                  'desktop.sidebar-campus-services',
                                ),
                                icon: TpIcons.activities,
                                label: '校园服务',
                                collapsed: collapsed,
                                onTap: onOpenCampusServices!,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (showAccountFooter) ...[
                      const SizedBox(height: TpTokens.space2),
                      Divider(height: 1, thickness: 0.5, color: colors.divider),
                      const SizedBox(height: TpTokens.space2),
                      _SidebarAccountTile(
                        summary: resolvedSummary,
                        collapsed: collapsed,
                        selected: accountSelected,
                        onTap: onOpenAccount,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarNavEntry {
  const _SidebarNavEntry({required this.index, required this.destination});

  final int index;
  final AppDestination destination;
}

class _SlidingSidebarNavList extends StatefulWidget {
  const _SlidingSidebarNavList({
    required this.entries,
    required this.selectedIndex,
    required this.collapsed,
    required this.itemSpacing,
    required this.badges,
    required this.onSelected,
  });

  final List<_SidebarNavEntry> entries;
  final int selectedIndex;
  final bool collapsed;
  final double itemSpacing;
  final Map<int, SidebarBadgeData> badges;
  final ValueChanged<int> onSelected;

  @override
  State<_SlidingSidebarNavList> createState() => _SlidingSidebarNavListState();
}

class _SlidingSidebarNavListState extends State<_SlidingSidebarNavList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _indicatorIndex = AnimationController.unbounded(
    vsync: this,
    value: _slotFor(widget.selectedIndex).clamp(0, _maxSlot).toDouble(),
  );

  int get _maxSlot =>
      widget.entries.isEmpty ? 0 : widget.entries.length - 1;

  int _slotFor(int destinationIndex) =>
      widget.entries.indexWhere((entry) => entry.index == destinationIndex);

  @override
  void didUpdateWidget(covariant _SlidingSidebarNavList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSlot = _slotFor(oldWidget.selectedIndex);
    final newSlot = _slotFor(widget.selectedIndex);
    if (newSlot >= 0 && (oldSlot != newSlot || oldWidget.entries.length != widget.entries.length)) {
      final target = newSlot.toDouble();
      final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduceMotion || oldSlot < 0) {
        _indicatorIndex.value = target;
      } else {
        unawaited(
          _indicatorIndex.animateWith(
            SpringSimulation(
              TgMotion.snappySpring,
              _indicatorIndex.value,
              target,
              0,
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _indicatorIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    final selectedBorder = colors.brand.withValues(
      alpha: colors.isDark ? 0.30 : 0.22,
    );
    final stride = DesktopSidebarTokens.navItemHeight + widget.itemSpacing;
    final activeSlot = _slotFor(widget.selectedIndex);
    final showIndicator = activeSlot >= 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _indicatorIndex,
          builder: (context, child) {
            final top = (_indicatorIndex.value * stride).clamp(
              0.0,
              _maxSlot * stride,
            );
            return Positioned(
              left: 0,
              right: 0,
              top: top,
              height: DesktopSidebarTokens.navItemHeight,
              child: IgnorePointer(child: child),
            );
          },
          child: AnimatedOpacity(
            key: const ValueKey('desktop.sidebar-active-indicator-opacity'),
            opacity: showIndicator ? 1.0 : 0.0,
            duration: appAnimationDuration(
              context,
              const Duration(milliseconds: 140),
            ),
            child: Material(
              key: const ValueKey('desktop.sidebar-active-indicator'),
              color: colors.opaqueBrandContainer,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: selectedBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: TpTokens.accentBarWidth,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(TpTokens.radiusBar),
                      ),
                    ),
                    foregroundDecoration: BoxDecoration(
                      color: colors.brand,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(TpTokens.radiusBar),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var slot = 0; slot < widget.entries.length; slot++) ...[
              DesktopSidebarItem(
                destination: widget.entries[slot].destination,
                selected: widget.entries[slot].index == widget.selectedIndex,
                collapsed: widget.collapsed,
                usesSlidingIndicator: true,
                badge: widget.badges[widget.entries[slot].index],
                onTap: () => widget.onSelected(widget.entries[slot].index),
              ),
              if (slot < widget.entries.length - 1)
                SizedBox(height: widget.itemSpacing),
            ],
          ],
        ),
      ],
    );
  }
}

class _SidebarDragHeader extends StatelessWidget {
  final double horizontalPadding;
  final bool collapsed;
  final bool showToggleButton;
  final VoidCallback onToggleCollapsed;

  const _SidebarDragHeader({
    required this.horizontalPadding,
    required this.collapsed,
    required this.showToggleButton,
    required this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = isMacOsDesktop() ? macOsTitlebarInset : 0.0;
    return MacOsWindowDragRegion(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          DesktopSidebarTokens.headerTopPadding + topInset,
          horizontalPadding,
          DesktopSidebarTokens.headerBottomPadding,
        ),
        child: _SidebarBrand(
          collapsed: collapsed,
          showToggleButton: showToggleButton,
          onToggleCollapsed: onToggleCollapsed,
        ),
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  final bool collapsed;
  final bool showToggleButton;
  final VoidCallback onToggleCollapsed;

  const _SidebarBrand({
    required this.collapsed,
    required this.showToggleButton,
    required this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final requiredExpandedWidth = DesktopSidebarTokens.iconColumnWidth +
            DesktopSidebarTokens.brandTextGap +
            DesktopSidebarTokens.minLabelWidth +
            (showToggleButton ? DesktopSidebarTokens.toggleButtonSize + 4 : 0);
        final canShowLabel =
            !collapsed && constraints.maxWidth >= requiredExpandedWidth;

        final logo = SizedBox(
          width: DesktopSidebarTokens.iconColumnWidth,
          child: Center(
            child: TpBrandMark(
              size: 28,
              semanticLabel: canShowLabel ? null : 'TechPie',
            ),
          ),
        );

        if (collapsed) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: DesktopSidebarTokens.brandHeight,
                child: Tooltip(message: 'TechPie', child: logo),
              ),
              if (showToggleButton) ...[
                const SizedBox(height: 6),
                _SidebarToggleButton(
                  collapsed: true,
                  compact: false,
                  onPressed: onToggleCollapsed,
                ),
              ],
            ],
          );
        }

        return SizedBox(
          height: DesktopSidebarTokens.brandHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              if (!canShowLabel)
                Tooltip(message: 'TechPie', child: logo)
              else
                logo,
              if (canShowLabel) ...[
                const SizedBox(width: DesktopSidebarTokens.brandTextGap),
                Expanded(
                  child: Text(
                    'TechPie',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TpTypography.cardTitle(colors).copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                if (showToggleButton) ...[
                  const SizedBox(width: TpTokens.space1),
                  _SidebarToggleButton(
                    collapsed: false,
                    compact: true,
                    onPressed: onToggleCollapsed,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SidebarCommandTrigger extends StatelessWidget {
  const _SidebarCommandTrigger({
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    final shortcutLabel = isMacOsDesktop() ? '⌘K' : 'Ctrl K';
    final tooltipMessage =
        isMacOsDesktop() ? '快速命令 (⌘K)' : '快速命令 (Ctrl+K)';

    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowLabel = !collapsed &&
            constraints.maxWidth >=
                DesktopSidebarTokens.iconColumnWidth +
                    DesktopSidebarTokens.navItemTextGap +
                    DesktopSidebarTokens.minLabelWidth;

        final button = Material(
          key: const ValueKey('desktop.command-palette-trigger'),
          color: colors.surfaceSubtle,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: colors.border == Colors.transparent
                ? BorderSide.none
                : BorderSide(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: colors.textPrimary.withValues(
              alpha: colors.isDark ? 0.06 : 0.04,
            ),
            child: SizedBox(
              height: 34,
              child: Row(
                children: [
                  const SizedBox(
                    width: DesktopSidebarTokens.iconColumnWidth,
                    child: Center(
                      child: Icon(TpIcons.search, size: 16),
                    ),
                  ),
                  if (canShowLabel) ...[
                    Expanded(
                      child: Text(
                        '搜索或跳转',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TpTypography.itemMeta(colors),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: TpTokens.space2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(TpTokens.radiusXs),
                          border: colors.border == Colors.transparent
                              ? Border.all(color: colors.divider, width: 0.5)
                              : Border.all(color: colors.border, width: 0.75),
                        ),
                        child: Text(
                          shortcutLabel,
                          style: TpTypography.badge(colors.textMuted).copyWith(
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

        if (canShowLabel) return button;
        return Tooltip(message: tooltipMessage, child: button);
      },
    );
  }
}

class _SidebarUtilityButton extends StatelessWidget {
  const _SidebarUtilityButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowLabel = !collapsed &&
            constraints.maxWidth >=
                DesktopSidebarTokens.iconColumnWidth +
                    DesktopSidebarTokens.navItemTextGap +
                    DesktopSidebarTokens.minLabelWidth;
        final item = Semantics(
          button: true,
          label: label,
          child: Material(
            key: buttonKey,
            color: colors.surface,
            shape: RoundedRectangleBorder(borderRadius: radius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              hoverColor: colors.textPrimary.withValues(
                alpha: colors.isDark ? 0.06 : 0.04,
              ),
              child: SizedBox(
                height: DesktopSidebarTokens.navItemHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: DesktopSidebarTokens.iconColumnWidth,
                      child: Center(
                        child: Icon(
                          icon,
                          size: TpTokens.iconM,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    if (canShowLabel) ...[
                      const SizedBox(width: DesktopSidebarTokens.navItemTextGap),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TpTypography.itemTitle(colors).copyWith(
                            fontSize: 14,
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: TpTokens.space3),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        if (canShowLabel) return item;
        return Tooltip(message: label, child: item);
      },
    );
  }
}

class _SidebarAccountTile extends StatelessWidget {
  const _SidebarAccountTile({
    required this.summary,
    required this.collapsed,
    required this.selected,
    this.onTap,
  });

  final DesktopSidebarAccountSummary summary;
  final bool collapsed;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    final selectedBorder = colors.brand.withValues(
      alpha: colors.isDark ? 0.30 : 0.22,
    );
    final title = summary.isLoggedIn && summary.displayName.isNotEmpty
        ? summary.displayName
        : '点击登录';
    final status = summary.isLoggedIn
        ? (summary.boundPlatformCount > 0
            ? '已绑定 ${summary.boundPlatformCount} 项服务'
            : '已登录')
        : '登录校园账号';

    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowLabel = !collapsed &&
            constraints.maxWidth >=
                DesktopSidebarTokens.iconColumnWidth +
                    DesktopSidebarTokens.navItemTextGap +
                    DesktopSidebarTokens.minLabelWidth;
        final avatar = Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: summary.isLoggedIn || selected
                ? colors.brandSoft
                : colors.surfaceSubtle,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: summary.isLoggedIn
              ? Text(
                  summary.avatarText,
                  style: TpTypography.badge(colors.brandInk).copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Icon(
                  TpIcons.profile,
                  size: 15,
                  color: selected ? colors.brandInk : colors.textMuted,
                ),
        );

        final tile = Semantics(
          selected: selected,
          button: true,
          label: summary.isLoggedIn ? '我的：$title' : '我的',
          child: Material(
            key: const ValueKey('desktop.sidebar-account'),
            color: selected ? colors.opaqueBrandContainer : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: selected
                  ? BorderSide(color: selectedBorder)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              hoverColor: colors.textPrimary.withValues(
                alpha: colors.isDark ? 0.06 : 0.04,
              ),
              child: SizedBox(
                height: collapsed ? 44 : 48,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (selected)
                      Positioned(
                        left: 0,
                        top: 10,
                        bottom: 10,
                        child: Container(
                          key: const ValueKey(
                            'desktop.sidebar-account-active-bar',
                          ),
                          width: TpTokens.accentBarWidth,
                          decoration: BoxDecoration(
                            color: colors.brand,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(TpTokens.radiusBar),
                            ),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        SizedBox(
                          width: DesktopSidebarTokens.iconColumnWidth,
                          child: Center(child: avatar),
                        ),
                        if (canShowLabel) ...[
                          const SizedBox(
                            width: DesktopSidebarTokens.navItemTextGap,
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TpTypography.itemTitle(colors).copyWith(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TpTypography.cardMeta(colors).copyWith(
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            TpIcons.settings,
                            size: 15,
                            color: selected ? colors.brandInk : colors.textMuted,
                          ),
                          const SizedBox(width: TpTokens.space2),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        if (canShowLabel) return tile;
        return Tooltip(
          message: summary.isLoggedIn ? '我的 · $title ($status)' : '我的 · $status',
          child: tile,
        );
      },
    );
  }
}

class _SidebarToggleButton extends StatelessWidget {
  final bool collapsed;
  final bool compact;
  final VoidCallback onPressed;

  const _SidebarToggleButton({
    required this.collapsed,
    required this.compact,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final shortcutHint = isMacOsDesktop() ? '⌘\\' : 'Ctrl+\\';
    final width = compact
        ? DesktopSidebarTokens.toggleButtonSize
        : DesktopSidebarTokens.iconColumnWidth;
    final height = compact ? DesktopSidebarTokens.toggleButtonSize : 34.0;

    return IconButton(
      key: const ValueKey('desktop.sidebar-toggle'),
      tooltip: collapsed
          ? '展开侧边栏 ($shortcutHint)'
          : '收起侧边栏 ($shortcutHint)',
      onPressed: onPressed,
      icon: Icon(
        collapsed ? TpIcons.sidebarExpand : TpIcons.sidebarCollapse,
        size: DesktopSidebarTokens.toggleIconSize,
      ),
      style: IconButton.styleFrom(
        fixedSize: Size(width, height),
        minimumSize: Size(width, height),
        padding: EdgeInsets.zero,
        foregroundColor: colors.textMuted,
        backgroundColor: Colors.transparent,
        hoverColor: colors.textPrimary.withValues(
          alpha: colors.isDark ? 0.06 : 0.04,
        ),
        highlightColor: colors.textPrimary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TpTokens.radiusS),
        ),
      ),
    );
  }
}
