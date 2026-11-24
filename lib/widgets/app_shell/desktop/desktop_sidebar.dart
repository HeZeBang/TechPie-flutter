import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../app_destination.dart';
import 'desktop_sidebar_item.dart';
import 'desktop_sidebar_tokens.dart';

class DesktopSidebar extends StatelessWidget {
  final List<AppDestination> destinations;
  final int selectedIndex;
  final bool collapsed;
  final bool showToggleButton;
  final ValueChanged<int> onSelected;
  final VoidCallback onToggleCollapsed;

  const DesktopSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.collapsed,
    this.showToggleButton = true,
    required this.onSelected,
    required this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final horizontalPadding = collapsed
        ? DesktopSidebarTokens.collapsedHorizontalPadding
        : DesktopSidebarTokens.expandedHorizontalPadding;
    final itemSpacing = DesktopSidebarTokens.navItemSpacing;

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
                            for (var index = 0;
                                index < destinations.length;
                                index++) ...[
                              DesktopSidebarItem(
                                destination: destinations[index],
                                selected: index == selectedIndex,
                                collapsed: collapsed,
                                onTap: () => onSelected(index),
                              ),
                              if (index < destinations.length - 1)
                                SizedBox(height: itemSpacing),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (showToggleButton) ...[
                      const SizedBox(height: TpTokens.space2),
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

class _SidebarDragHeader extends StatelessWidget {
  final double horizontalPadding;
  final bool collapsed;

  const _SidebarDragHeader({
    required this.horizontalPadding,
    required this.collapsed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesktopSidebarTokens.headerHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          DesktopSidebarTokens.headerTopPadding,
          horizontalPadding,
          DesktopSidebarTokens.headerBottomPadding,
        ),
        child: _SidebarBrand(collapsed: collapsed),
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

          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                width: DesktopSidebarTokens.iconColumnWidth,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.opaqueBrandContainer,
                      borderRadius: BorderRadius.circular(TpTokens.radiusS),
                    ),
                    child: Icon(
                      TpIcons.graduation,
                      size: TpTokens.iconM - 2,
                      color: colors.brandInk,
                    ),
                  ),
                ),
              ),
              if (canShowLabel) ...[
                const SizedBox(width: DesktopSidebarTokens.brandTextGap),
                Expanded(
                  child: Text(
                    'TechPie',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TpTypography.cardTitle(colors).copyWith(
                      fontSize: 16,
                      letterSpacing: -0.2,
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
