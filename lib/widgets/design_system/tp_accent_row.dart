import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';

/// List row with a 3dp vertical accent bar on the left, bold title, muted
/// metadata, and an optional trailing badge or chevron.
class TpAccentRow extends StatelessWidget {
  const TpAccentRow({
    super.key,
    required this.accentColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.opacity = 1.0,
    this.showDivider = false,
    this.boldTitle = false,
  });

  final Color accentColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double opacity;
  final bool showDivider;
  final bool boldTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final baseStyle = TpTypography.itemTitle(colors);
    final titleStyle = boldTitle
        ? baseStyle.copyWith(fontWeight: FontWeight.w700)
        : baseStyle;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TpTokens.cardPaddingHorizontal,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: TpTokens.accentBarWidth,
            height: subtitle != null && subtitle!.isNotEmpty ? 34 : 20,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(TpTokens.radiusBar),
            ),
          ),
          const SizedBox(width: TpTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TpTypography.itemMeta(colors),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: TpTokens.space2),
            trailing!,
          ],
        ],
      ),
    );

    Widget content = Column(
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
            padding: const EdgeInsets.only(
              left: TpTokens.cardPaddingHorizontal +
                  TpTokens.accentBarWidth +
                  TpTokens.space3,
              right: TpTokens.cardPaddingHorizontal,
            ),
            child: Divider(height: 1, thickness: 0.5, color: colors.divider),
          ),
      ],
    );

    if (opacity < 1.0) {
      content = Opacity(opacity: opacity, child: content);
    }

    return content;
  }
}
