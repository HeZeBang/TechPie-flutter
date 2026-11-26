import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_density.dart';
import '../../theme/tp_icons.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';

/// Unified grouped list row for settings, account hubs, and detail sheets.
class TpListRow extends StatelessWidget {
  const TpListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.leading,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.showDivider = false,
    this.destructive = false,
    this.subtitleMaxLines = 2,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final IconData? icon;
  final Widget? leading;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool showDivider;
  final bool destructive;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final density = context.tpDensity;
    final effectiveTitleColor =
        destructive ? colors.dangerRed : colors.textPrimary;
    final effectiveIconColor =
        iconColor ?? (destructive ? colors.dangerRed : colors.brandInk);
    final hasLeading = leading != null || icon != null;

    final row = Padding(
      padding: density.rowPadding,
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(
              width: density.iconSize,
              height: density.iconSize,
              child: Center(child: leading),
            ),
            const SizedBox(width: TpTokens.space3),
          ] else if (icon != null) ...[
            Icon(
              icon,
              size: density.iconSize,
              color: effectiveIconColor,
            ),
            const SizedBox(width: TpTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TpTypography.itemTitle(colors).copyWith(
                    fontWeight: FontWeight.w500,
                    color: effectiveTitleColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TpTypography.itemMeta(colors),
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (value != null && value!.isNotEmpty) ...[
            const SizedBox(width: TpTokens.space2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                value!,
                style: TpTypography.itemMeta(colors),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: TpTokens.space2),
            trailing!,
          ] else if (showChevron) ...[
            const SizedBox(width: TpTokens.space1),
            Icon(
              TpIcons.chevronRight,
              size: TpTokens.iconS,
              color: colors.textMuted,
            ),
          ],
        ],
      ),
    );

    final dividerIndent = hasLeading
        ? density.cardPaddingHorizontal + density.iconSize + TpTokens.space3
        : density.cardPaddingHorizontal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onTap == null)
          row
        else
          InkWell(
            onTap: onTap,
            hoverColor: colors.textPrimary.withValues(
              alpha: colors.isDark ? 0.06 : 0.04,
            ),
            splashColor: colors.brandSoft,
            highlightColor: colors.surfacePressed.withValues(alpha: 0.35),
            child: row,
          ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(
              left: dividerIndent,
              right: density.cardPaddingHorizontal,
            ),
            child: Divider(height: 1, thickness: 0.5, color: colors.divider),
          ),
      ],
    );
  }
}
