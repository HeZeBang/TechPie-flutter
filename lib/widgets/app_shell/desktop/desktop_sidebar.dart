import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../theme/theme.dart';
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
    this.onOpenAccount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final horizontalPadding = collapsed
        ? DesktopSidebarTokens.collapsedHorizontalPadding
        : DesktopSidebarTokens.expandedHorizontalPadding;
    final itemSpacing = DesktopSidebarTokens.navItemSpacing;
    final hasFooterItems = accountSummary != null || showToggleButton;

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
                              destinations: destinations,
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
                                  vertical: TpTokens.space2,
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
                    if (hasFooterItems) const SizedBox(height: TpTokens.space2),
                    if (accountSummary != null) ...[
                      Divider(height: 1, thickness: 0.5, color: colors.divider),
                      const SizedBox(height: TpTokens.space2),
                      _SidebarAccountTile(
                        summary: accountSummary!,
                        collapsed: collapsed,
                        onTap: onOpenAccount,
                      ),
                    ],
                    if (showToggleButton) ...[
                      if (accountSummary != null)
                        const SizedBox(height: TpTokens.space1),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: _SidebarToggleButton(
                          collapsed: collapsed,
                          onPressed: onToggleCollapsed,
                        ),
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

class _SlidingSidebarNavList extends StatefulWidget {
  const _SlidingSidebarNavList({
    required this.destinations,
    required this.selectedIndex,
    required this.collapsed,
    required this.itemSpacing,
    required this.badges,
    required this.onSelected,
  });

  final List<AppDestination> destinations;
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
    value: widget.selectedIndex.toDouble(),
  );

  @override
  void didUpdateWidget(covariant _SlidingSidebarNavList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final target = widget.selectedIndex.toDouble();
      final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduceMotion) {
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
    if (widget.destinations.isEmpty) return const SizedBox.shrink();
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    final selectedBorder = colors.brand.withValues(
      alpha: colors.isDark ? 0.30 : 0.22,
    );
    final stride = DesktopSidebarTokens.navItemHeight + widget.itemSpacing;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _indicatorIndex,
          builder: (context, child) {
            final top = (_indicatorIndex.value * stride).clamp(
              0.0,
              (widget.destinations.length - 1) * stride,
            );
            return Positioned(
              left: 0,
              right: 0,
              top: top,
              height: DesktopSidebarTokens.navItemHeight,
              child: IgnorePointer(child: child),
            );
          },
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < widget.destinations.length; index++) ...[
              DesktopSidebarItem(
                destination: widget.destinations[index],
                selected: index == widget.selectedIndex,
                collapsed: widget.collapsed,
                usesSlidingIndicator: true,
                badge: widget.badges[index],
                onTap: () => widget.onSelected(index),
              ),
              if (index < widget.destinations.length - 1)
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

  const _SidebarDragHeader({
    required this.horizontalPadding,
    required this.collapsed,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = isMacOsDesktop() ? macOsTitlebarInset : 0.0;
    return MacOsWindowDragRegion(
      child: SizedBox(
        height: DesktopSidebarTokens.headerHeight + topInset,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            DesktopSidebarTokens.headerTopPadding + topInset,
            horizontalPadding,
            DesktopSidebarTokens.headerBottomPadding,
          ),
          child: _SidebarBrand(collapsed: collapsed),
        ),
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  final bool collapsed;

  const _SidebarBrand({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;

    return SizedBox(
      height: DesktopSidebarTokens.brandHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canShowLabel = !collapsed &&
              constraints.maxWidth >=
                  DesktopSidebarTokens.iconColumnWidth +
                      DesktopSidebarTokens.brandTextGap +
                      DesktopSidebarTokens.minLabelWidth;

          final logo = SizedBox(
            width: DesktopSidebarTokens.iconColumnWidth,
            child: Center(
              child: TpBrandMark(
                size: 40,
                semanticLabel: canShowLabel ? null : 'TechPie',
              ),
            ),
          );

          return Row(
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
                      fontSize: 17.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
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
              height: 36,
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
    this.onTap,
  });

  final DesktopSidebarAccountSummary summary;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
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
            color: summary.isLoggedIn ? colors.brandSoft : colors.surfaceSubtle,
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
              : Icon(TpIcons.profile, size: 15, color: colors.textMuted),
        );

        final tile = Material(
          key: const ValueKey('desktop.sidebar-account'),
          color: Colors.transparent,
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
                    child: Center(child: avatar),
                  ),
                  if (canShowLabel) ...[
                    const SizedBox(width: DesktopSidebarTokens.navItemTextGap),
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
                    const SizedBox(width: TpTokens.space2),
                  ],
                ],
              ),
            ),
          ),
        );

        if (canShowLabel) return tile;
        return Tooltip(
          message: summary.isLoggedIn ? '$title · $status' : status,
          child: tile,
        );
      },
    );
  }
}

class _SidebarToggleButton extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onPressed;

  const _SidebarToggleButton({
    required this.collapsed,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;

    return IconButton(
      key: const ValueKey('desktop.sidebar-toggle'),
      tooltip: collapsed ? '展开侧边栏' : '收起侧边栏',
      onPressed: onPressed,
      icon: SizedBox(
        width: DesktopSidebarTokens.iconColumnWidth,
        height: DesktopSidebarTokens.navItemHeight,
        child: Center(
          child: Icon(
            collapsed ? TpIcons.sidebarExpand : TpIcons.sidebarCollapse,
            size: TpTokens.iconM,
          ),
        ),
      ),
      style: IconButton.styleFrom(
        fixedSize: const Size(
          DesktopSidebarTokens.iconColumnWidth,
          DesktopSidebarTokens.navItemHeight,
        ),
        minimumSize: const Size(
          DesktopSidebarTokens.iconColumnWidth,
          DesktopSidebarTokens.navItemHeight,
        ),
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
