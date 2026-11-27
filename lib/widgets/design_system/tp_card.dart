import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_density.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';
import 'tp_press_scale.dart';
import 'tp_tap_surface.dart';

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
    this.enablePressScale = true,
    this.pressedScale = 0.98,
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
  final bool enablePressScale;
  final double pressedScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final density = context.tpDensity;
    final resolvedBorder = borderColor ?? colors.border;
    final radius = BorderRadius.circular(borderRadius);

    Widget content = child;
    if (title != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: headerPadding ?? density.cardHeaderPadding,
            child: Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(
                    leadingIcon,
                    size: TpTokens.iconS,
                    color: colors.brandInk,
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
    final Widget surfaceContent = colors.isDark
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              content,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.07),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        : content;

    final materialCard = Material(
      color: color ?? colors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: !interactive
          ? surfaceContent
          : TpTapSurface(
              style: TpTapFeedbackStyle.card,
              borderRadius: radius,
              onTap: onTap,
              onLongPress: onLongPress,
              enablePressScale: false,
              child: surfaceContent,
            ),
    );

    final shadows = colors.isDark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.038),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ];

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadows,
      ),
      child: materialCard,
    );

    if (!interactive || !enablePressScale) return card;
    return TpPressScale(
      pressedScale: pressedScale,
      child: card,
    );
  }
}
