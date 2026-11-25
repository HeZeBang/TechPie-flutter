import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../app_destination.dart';
import 'desktop_sidebar_tokens.dart';

class DesktopSidebarItem extends StatelessWidget {
  final AppDestination destination;
  final bool selected;
  final bool collapsed;
  final bool usesSlidingIndicator;
  final SidebarBadgeData? badge;
  final VoidCallback onTap;

  const DesktopSidebarItem({
    super.key,
    required this.destination,
    required this.selected,
    required this.collapsed,
    this.usesSlidingIndicator = false,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final foreground = selected ? colors.textPrimary : colors.textSecondary;
    final iconColor = selected ? colors.brandInk : colors.textMuted;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    final selectedBorder = colors.brand.withValues(
      alpha: colors.isDark ? 0.30 : 0.22,
    );
    final showOwnSelectionSurface = selected && !usesSlidingIndicator;

    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowLabel = !collapsed &&
            constraints.maxWidth >=
                DesktopSidebarTokens.iconColumnWidth +
                    DesktopSidebarTokens.navItemTextGap +
                    DesktopSidebarTokens.minLabelWidth;

        final activeBadge = badge != null && badge!.count > 0 ? badge : null;
        final semanticLabel = activeBadge != null
            ? '${destination.label} (${activeBadge.formatted})'
            : destination.label;

        final hoverOverlay = colors.textPrimary.withValues(
          alpha: colors.isDark ? 0.06 : 0.04,
        );
        final iconWidget = Icon(
          selected ? destination.selectedIcon : destination.icon,
          size: TpTokens.iconM,
          color: iconColor,
        );
        final item = Semantics(
          selected: selected,
          button: true,
          label: semanticLabel,
          child: Material(
            type: usesSlidingIndicator
                ? MaterialType.transparency
                : MaterialType.canvas,
            color: usesSlidingIndicator
                ? null
                : (showOwnSelectionSurface
                    ? colors.opaqueBrandContainer
                    : colors.surface),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: showOwnSelectionSurface
                  ? BorderSide(color: selectedBorder)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              hoverColor: hoverOverlay,
              highlightColor: colors.textPrimary.withValues(alpha: 0.06),
              splashColor: colors.brand.withValues(alpha: 0.10),
              focusColor: colors.brand.withValues(alpha: 0.08),
              child: SizedBox(
                height: DesktopSidebarTokens.navItemHeight,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (showOwnSelectionSurface)
                      Positioned(
                        left: 0,
                        top: 10,
                        bottom: 10,
                        child: Container(
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
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: DesktopSidebarTokens.iconColumnWidth,
                          child: Center(
                            child: !canShowLabel && activeBadge != null
                                ? Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      iconWidget,
                                      Positioned(
                                        right: -3,
                                        top: -3,
                                        child: Container(
                                          key: ValueKey<String>(
                                            'sidebar-badge-dot-${destination.label}',
                                          ),
                                          width: 8.5,
                                          height: 8.5,
                                          decoration: BoxDecoration(
                                            color: activeBadge.urgent
                                                ? colors.dangerRed
                                                : colors.textMuted,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: colors.surface,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : iconWidget,
                          ),
                        ),
                        if (canShowLabel) ...[
                          const SizedBox(
                            width: DesktopSidebarTokens.navItemTextGap,
                          ),
                          Expanded(
                            child: Text(
                              destination.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TpTypography.itemTitle(colors).copyWith(
                                fontSize: 14,
                                color: foreground,
                                fontWeight:
                                    selected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (activeBadge != null) ...[
                            const SizedBox(width: TpTokens.space2),
                            Container(
                              key: ValueKey<String>(
                                'sidebar-badge-${destination.label}',
                              ),
                              constraints: const BoxConstraints(minWidth: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: activeBadge.urgent
                                    ? colors.dangerRed
                                    : colors.surfaceSubtle,
                                borderRadius: BorderRadius.circular(
                                  TpTokens.radiusPill,
                                ),
                              ),
                              child: Text(
                                activeBadge.formatted,
                                textAlign: TextAlign.center,
                                style: TpTypography.badge(
                                  activeBadge.urgent
                                      ? Colors.white
                                      : colors.textSecondary,
                                ).copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: TpTokens.space3),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        if (canShowLabel) return item;
        return Tooltip(message: semanticLabel, child: item);
      },
    );
  }
}
