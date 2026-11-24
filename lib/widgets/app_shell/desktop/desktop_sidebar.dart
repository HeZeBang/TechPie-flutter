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

class DesktopSidebar extends StatelessWidget {
  final List<AppDestination> destinations;
  final int selectedIndex;
  final bool collapsed;
  final bool showToggleButton;
  final Map<int, SidebarBadgeData> badges;
  final ValueChanged<int> onSelected;
  final VoidCallback onToggleCollapsed;

  const DesktopSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.collapsed,
    this.showToggleButton = true,
    this.badges = const <int, SidebarBadgeData>{},
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
                        child: _SlidingSidebarNavList(
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
