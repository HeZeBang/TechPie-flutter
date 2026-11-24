import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';

enum TpBadgeTone { brand, info, success, warning, danger, muted }

/// Soft-tinted pill badge for concise status indicators (`进行中`, `在线`, etc.).
class TpBadge extends StatelessWidget {
  const TpBadge({
    super.key,
    required this.label,
    this.tone = TpBadgeTone.brand,
    this.icon,
  });

  final String label;
  final TpBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final (fg, bg) = _resolveColors(colors);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TpTokens.space2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TpTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: TpTokens.iconXs - 2, color: fg),
            const SizedBox(width: TpTokens.space1),
          ],
          Text(
            label,
            style: TpTypography.badge(fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  (Color, Color) _resolveColors(TpColors colors) {
    final alpha = colors.isDark ? 0.16 : 0.10;
    return switch (tone) {
      TpBadgeTone.brand => (colors.brand, colors.brandSoft),
      TpBadgeTone.info => (
          colors.infoBlue,
          colors.infoBlue.withValues(alpha: alpha),
        ),
      TpBadgeTone.success => (
          colors.successGreen,
          colors.successGreen.withValues(alpha: alpha),
        ),
      TpBadgeTone.warning => (
          colors.warningAmber,
          colors.warningAmber.withValues(alpha: alpha),
        ),
      TpBadgeTone.danger => (
          colors.dangerRed,
          colors.dangerRed.withValues(alpha: alpha),
        ),
      TpBadgeTone.muted => (colors.textMuted, colors.surfaceSubtle),
    };
  }
}
