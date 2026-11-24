import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../app_destination.dart';
import 'desktop_sidebar_tokens.dart';

class DesktopSidebarItem extends StatelessWidget {
  final AppDestination destination;
  final bool selected;
  final bool collapsed;
  final bool usesSlidingIndicator;
  final VoidCallback onTap;

  const DesktopSidebarItem({
    super.key,
    required this.destination,
    required this.selected,
    required this.collapsed,
    this.usesSlidingIndicator = false,
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

        final hoverOverlay = colors.textPrimary.withValues(
          alpha: colors.isDark ? 0.06 : 0.04,
        );
        final item = Semantics(
          selected: selected,
          button: true,
          label: destination.label,
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
                            child: Icon(
                              selected
                                  ? destination.selectedIcon
                                  : destination.icon,
                              size: TpTokens.iconM,
                              color: iconColor,
                            ),
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
        return Tooltip(message: destination.label, child: item);
      },
    );
  }
}
