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
  final VoidCallback? onBrandTap;
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
    this.onBrandTap,
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

    final sidebarBg = colors.isAmoled
        ? const Color(0xFF0A0A0C)
        : (colors.isDark ? const Color(0xFF141417) : const Color(0xFFF6F6F9));

    return ColoredBox(
      color: sidebarBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 150,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.75, -0.85),
                    radius: 1.15,
                    colors: [
                      TpTokens.techRedDark.withValues(
                        alpha: colors.isDark ? 0.08 : 0.045,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
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
                  onBrandTap: onBrandTap,
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
                            child: _SlidingSidebarNavList(
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
                          ),
                        ),
                        if (showAccountFooter) ...[
                          const SizedBox(height: TpTokens.space2),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: colors.divider,
                          ),
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
        ],
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
    final pillFill = colors.isDark
        ? Colors.white.withValues(alpha: 0.085)
        : colors.surface;
    final pillBorder = colors.isDark
        ? Colors.white.withValues(alpha: 0.11)
        : const Color(0x10000000);
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: colors.isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 1.5,
                          offset: const Offset(0, 0.5),
                        ),
                      ],
              ),
              child: Material(
                key: const ValueKey('desktop.sidebar-active-indicator'),
                color: pillFill,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide(color: pillBorder, width: 0.75),
                ),
                clipBehavior: Clip.antiAlias,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var slot = 0; slot < widget.entries.length; slot++) ...[
              DesktopSidebarItem(
                key: widget.entries[slot].destination.label == '校园服务'
                    ? const ValueKey('desktop.sidebar-campus-services')
                    : ValueKey('desktop.sidebar-nav-${widget.entries[slot].index}'),
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
  final VoidCallback? onBrandTap;

  const _SidebarDragHeader({
    required this.horizontalPadding,
    required this.collapsed,
    required this.showToggleButton,
    required this.onToggleCollapsed,
    this.onBrandTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMac = isMacOsDesktop();
    if (collapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMac)
            const MacOsWindowDragRegion(
              child: SizedBox(
                height: DesktopSidebarTokens.macOsTitlebarRowHeight,
              ),
            ),
          if (showToggleButton)
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                isMac ? 4 : DesktopSidebarTokens.headerTopPadding,
                horizontalPadding,
                TpTokens.space2,
              ),
              child: Center(
                child: _SidebarToggleButton(
                  collapsed: true,
                  compact: false,
                  onPressed: onToggleCollapsed,
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              showToggleButton
                  ? 0
                  : (isMac ? 4 : DesktopSidebarTokens.headerTopPadding),
              horizontalPadding,
              DesktopSidebarTokens.headerBottomPadding,
            ),
            child: Center(
              child: _SidebarBrandTile(
                canShowLabel: false,
                compactCollapsed: true,
                onTap: onBrandTap,
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minExpandedWidth = DesktopSidebarTokens.brandIconSize +
            12 +
            DesktopSidebarTokens.brandTextGap +
            DesktopSidebarTokens.minLabelWidth;
        final innerWidth = (constraints.maxWidth - 2 * horizontalPadding)
            .clamp(0.0, double.infinity);
        final canShowLabel = innerWidth >= minExpandedWidth;

        if (isMac) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: DesktopSidebarTokens.macOsTitlebarRowHeight,
                child: Row(
                  children: [
                    const Expanded(
                      child: MacOsWindowDragRegion(
                        child: SizedBox.expand(),
                      ),
                    ),
                    if (showToggleButton && canShowLabel)
                      Padding(
                        padding: EdgeInsets.only(
                          right: (horizontalPadding - 2).clamp(0.0, 24.0),
                        ),
                        child: _SidebarToggleButton(
                          collapsed: false,
                          compact: true,
                          onPressed: onToggleCollapsed,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  2,
                  horizontalPadding,
                  DesktopSidebarTokens.headerBottomPadding,
                ),
                child: _SidebarBrandTile(
                  canShowLabel: canShowLabel,
                  onTap: onBrandTap,
                ),
              ),
            ],
          );
        }

        final canShowToggleWithLabel = showToggleButton &&
            innerWidth >=
                minExpandedWidth +
                    TpTokens.space1 +
                    DesktopSidebarTokens.toggleButtonSize;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            DesktopSidebarTokens.headerTopPadding,
            horizontalPadding,
            DesktopSidebarTokens.headerBottomPadding,
          ),
          child: SizedBox(
            height: DesktopSidebarTokens.brandHeight,
            child: Row(
              children: [
                Expanded(
                  child: _SidebarBrandTile(
                    canShowLabel: canShowLabel,
                    onTap: onBrandTap,
                  ),
                ),
                if (canShowToggleWithLabel) ...[
                  const SizedBox(width: TpTokens.space1),
                  _SidebarToggleButton(
                    collapsed: false,
                    compact: true,
                    onPressed: onToggleCollapsed,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarBrandTile extends StatelessWidget {
  const _SidebarBrandTile({
    required this.canShowLabel,
    this.compactCollapsed = false,
    this.onTap,
  });

  final bool canShowLabel;
  final bool compactCollapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);

    final Widget content = compactCollapsed
        ? const SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: TpBrandMark(
                size: DesktopSidebarTokens.brandIconSize,
                semanticLabel: 'TechPie',
              ),
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesktopSidebarTokens.brandHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisAlignment: canShowLabel
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  TpBrandMark(
                    size: DesktopSidebarTokens.brandIconSize,
                    semanticLabel: canShowLabel ? null : 'TechPie',
                  ),
                  if (canShowLabel) ...[
                    const SizedBox(width: DesktopSidebarTokens.brandTextGap),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TpBrandWordmark(fontSize: 17),
                          SizedBox(height: 2),
                          TpBrandSubtitle(
                            prefix: 'SHANGHAITECH',
                            accentSuffix: '',
                            fontSize: 9.5,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );

    final tile = Material(
      key: const ValueKey('desktop.sidebar-brand'),
      type: MaterialType.transparency,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: radius,
              hoverColor: colors.textPrimary.withValues(
                alpha: colors.isDark ? 0.05 : 0.035,
              ),
              highlightColor: colors.textPrimary.withValues(alpha: 0.06),
              splashColor: colors.brand.withValues(alpha: 0.08),
              child: content,
            ),
    );

    if (onTap == null) return tile;
    return Semantics(
      button: true,
      label: 'TechPie 返回首页',
      child: Tooltip(
        message: '返回首页',
        child: tile,
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
          color: colors.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: colors.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0x12000000),
              width: 0.75,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: colors.textPrimary.withValues(
              alpha: colors.isDark ? 0.06 : 0.04,
            ),
            child: SizedBox(
              height: 32,
              child: Row(
                children: [
                  SizedBox(
                    width: DesktopSidebarTokens.iconColumnWidth,
                    child: Center(
                      child: Icon(
                        TpIcons.search,
                        size: 14.5,
                        color: colors.textMuted,
                      ),
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
    final pillFill = colors.isDark
        ? Colors.white.withValues(alpha: 0.085)
        : colors.surface;
    final pillBorder = colors.isDark
        ? Colors.white.withValues(alpha: 0.11)
        : const Color(0x10000000);
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
            color: colors.isDark
                ? Colors.white.withValues(alpha: 0.10)
                : const Color(0xFFE8E8EE),
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: colors.brand.withValues(alpha: 0.35),
                    width: 0.75,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: summary.isLoggedIn
              ? Text(
                  summary.avatarText,
                  style: TpTypography.badge(colors.textPrimary).copyWith(
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

        final activeMaterial = Material(
          key: const ValueKey('desktop.sidebar-account'),
          color: selected ? pillFill : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: selected
                ? BorderSide(color: pillBorder, width: 0.75)
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
                children: [
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
                        if (selected) ...[
                          Container(
                            key: const ValueKey(
                              'desktop.sidebar-account-active-bar',
                            ),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: colors.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Icon(
                          TpIcons.settings,
                          size: 15,
                          color: selected ? colors.brandInk : colors.textMuted,
                        ),
                        const SizedBox(width: TpTokens.space2),
                      ],
                    ],
                  ),
                  if (selected && !canShowLabel)
                    Positioned(
                      right: 5,
                      top: 5,
                      child: Container(
                        key: const ValueKey(
                          'desktop.sidebar-account-active-bar',
                        ),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colors.brand,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        final tile = Semantics(
          selected: selected,
          button: true,
          label: summary.isLoggedIn ? '我的：$title' : '我的',
          child: (selected && !colors.isDark)
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: activeMaterial,
                )
              : activeMaterial,
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
