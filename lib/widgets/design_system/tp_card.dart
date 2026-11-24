import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';

/// Unified surface-contrast card container for TechPie.
///
/// Light mode relies purely on `#FFFFFF` over `#F2F2F7` canvas contrast (no
/// border); Dark and AMOLED modes add a hairline translucent border for crisp
/// edge definition.
class TpCard extends StatelessWidget {
  const TpCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.leadingIcon,
    this.padding,
    this.headerPadding,
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderColor,
    this.borderWidth = 0.75,
    this.borderRadius = TpTokens.radiusM,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final IconData? leadingIcon;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? headerPadding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final resolvedBorder = borderColor ?? colors.border;
    final radius = BorderRadius.circular(borderRadius);

    Widget content = child;
    if (title != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: headerPadding ??
                const EdgeInsets.fromLTRB(
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.cardPaddingVertical,
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.space2,
                ),
            child: Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(
                    leadingIcon,
                    size: TpTokens.iconS,
                    color: colors.brand,
                  ),
                  const SizedBox(width: TpTokens.space2),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: TpTypography.cardTitle(colors),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: TpTokens.space2),
                  DefaultTextStyle(
                    style: TpTypography.cardMeta(colors),
                    child: trailing!,
                  ),
                ],
              ],
            ),
          ),
          if (padding != null) Padding(padding: padding!, child: child) else child,
        ],
      );
    } else if (padding != null) {
      content = Padding(padding: padding!, child: child);
    }

    final shape = RoundedRectangleBorder(
      borderRadius: radius,
      side: resolvedBorder == Colors.transparent
          ? BorderSide.none
          : BorderSide(color: resolvedBorder, width: borderWidth),
    );

    final interactive = onTap != null || onLongPress != null;

    return Material(
      color: color ?? colors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: !interactive
          ? content
          : InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: radius,
              splashColor: colors.brandSoft,
              highlightColor: colors.surfacePressed.withValues(alpha: 0.4),
              child: content,
            ),
    );
  }
}
