import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';
import 'tp_tap_surface.dart';

/// Deadline/task row featuring title, urgency countdown, optional subtitle,
/// and a thin rounded progress indicator bar.
class TpProgressRow extends StatelessWidget {
  const TpProgressRow({
    super.key,
    required this.title,
    required this.trailingLabel,
    required this.progress,
    required this.color,
    this.trailingColor,
    this.highlightTrailing = false,
    this.subtitle,
    this.onTap,
    this.showDivider = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: TpTokens.cardPaddingHorizontal,
      vertical: 11,
    ),
  });

  final String title;
  final String trailingLabel;
  final double progress;
  final Color color;
  final Color? trailingColor;
  final bool highlightTrailing;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showDivider;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final clamped = progress.clamp(0.05, 1.0);
    final resolvedTrailingColor = trailingColor ?? color;
    final Widget trailing = highlightTrailing
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: resolvedTrailingColor.withValues(
                alpha: colors.isDark ? 0.16 : 0.10,
              ),
              borderRadius: BorderRadius.circular(TpTokens.radiusPill),
            ),
            child: Text(
              trailingLabel,
              style: TpTypography.badge(resolvedTrailingColor),
              maxLines: 1,
            ),
          )
        : Text(
            trailingLabel,
            style: TpTypography.badge(resolvedTrailingColor),
            maxLines: 1,
          );

    final body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TpTypography.itemTitle(colors),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: TpTokens.space2),
              trailing,
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TpTypography.itemMeta(colors),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 7),
          TpProgressBar(progress: clamped, color: color),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onTap == null)
          body
        else
          TpTapSurface(
            style: TpTapFeedbackStyle.row,
            onTap: onTap,
            child: body,
          ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TpTokens.cardPaddingHorizontal,
            ),
            child: Divider(height: 1, thickness: 0.5, color: colors.divider),
          ),
      ],
    );
  }
}

/// Reusable thin rounded progress bar (3dp height, subtle neutral track).
class TpProgressBar extends StatelessWidget {
  const TpProgressBar({
    super.key,
    required this.progress,
    required this.color,
    this.height = 3.0,
  });

  final double progress;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusBar);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        color: colors.surfaceSubtle,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: radius,
            ),
          ),
        ),
      ),
    );
  }
}
