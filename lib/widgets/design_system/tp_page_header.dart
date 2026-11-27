import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';
import 'tp_press_scale.dart';
import 'tp_tap_surface.dart';

/// Compact typographic header for root screens (subtitle + bold title + action).
class TpPageHeader extends StatelessWidget {
  const TpPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.padding = const EdgeInsets.only(
      top: TpTokens.space1,
      bottom: TpTokens.space2,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subtitleWidget != null) ...[
                  subtitleWidget!,
                  const SizedBox(height: 3),
                ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                  Text(
                    subtitle!,
                    style: TpTypography.pageSubtitle(colors),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  style: TpTypography.pageTitle(colors),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: TpTokens.space3),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Visual tone for [TpAvatarBadge].
enum TpAvatarBadgeTone { brandSoft, neutral, brand }

/// Circular tactile avatar pill used in page headers.
class TpAvatarBadge extends StatelessWidget {
  const TpAvatarBadge({
    super.key,
    required this.text,
    this.onTap,
    this.tooltip,
    this.size = 36,
    this.tone = TpAvatarBadgeTone.brandSoft,
  });

  final String text;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final TpAvatarBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final (fillColor, labelColor) = switch (tone) {
      TpAvatarBadgeTone.brandSoft => (colors.brandSoft, colors.brandInk),
      TpAvatarBadgeTone.neutral => (colors.surfaceSubtle, colors.textPrimary),
      TpAvatarBadgeTone.brand => (colors.brand, colors.onBrand),
    };

    final content = SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: labelColor,
            letterSpacing: 0.2,
            fontFamilyFallback: TpTypography.fontFamilyFallback,
          ),
          maxLines: 1,
        ),
      ),
    );

    final badge = Material(
      color: fillColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : TpTapSurface(
              style: TpTapFeedbackStyle.button,
              customBorder: const CircleBorder(),
              pressedColor:
                  tone == TpAvatarBadgeTone.brand ? colors.onBrand : null,
              enablePressScale: false,
              onTap: onTap,
              child: content,
            ),
    );

    final interactiveBadge = onTap == null
        ? badge
        : TpPressScale(
            pressedScale: 0.92,
            child: badge,
          );

    if (tooltip == null) return interactiveBadge;
    return Tooltip(message: tooltip!, child: interactiveBadge);
  }
}
