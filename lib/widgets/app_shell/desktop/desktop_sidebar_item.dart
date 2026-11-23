import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../app_destination.dart';
import 'desktop_sidebar_tokens.dart';

class DesktopSidebarItem extends StatelessWidget {
  final AppDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const DesktopSidebarItem({
    super.key,
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final foreground = selected ? colors.brand : colors.textSecondary;
    final iconColor = selected ? colors.brand : colors.textMuted;
    final radius = BorderRadius.circular(TpTokens.radiusS);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowLabel = !collapsed &&
            constraints.maxWidth >=
                DesktopSidebarTokens.iconColumnWidth +
                    DesktopSidebarTokens.navItemTextGap +
                    DesktopSidebarTokens.minLabelWidth;

        return Material(
          color: selected ? colors.brandSoft : Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: selected ? colors.brandSoft : colors.surfaceSubtle,
            splashColor: colors.brandSoft,
            child: SizedBox(
              height: DesktopSidebarTokens.navItemHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: DesktopSidebarTokens.iconColumnWidth,
                    child: Center(
                      child: Icon(
                        selected ? destination.selectedIcon : destination.icon,
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
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
