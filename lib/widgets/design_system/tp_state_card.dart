import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_density.dart';
import '../../theme/tp_icons.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';
import '../adaptive_button.dart';
import 'tp_card.dart';

/// Semantic tone for [TpStateCard] icon tiles.
enum TpStateTone { neutral, brand, warning, danger, success }

/// Unified Empty, Error, and Prerequisite state card built on [TpCard] and
/// [AdaptiveButton] with zero raw colors or platform visual branching.
class TpStateCard extends StatelessWidget {
  const TpStateCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.tone = TpStateTone.neutral,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.primaryActionSfSymbol,
    this.onPrimaryAction,
    this.primaryLoading = false,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.secondaryActionSfSymbol,
    this.onSecondaryAction,
    this.footer,
    this.compact = false,
  });

  const TpStateCard.empty({
    super.key,
    this.icon = TpIcons.inbox,
    required this.title,
    this.message,
    this.tone = TpStateTone.neutral,
    this.primaryActionLabel,
    this.primaryActionIcon = TpIcons.refresh,
    this.primaryActionSfSymbol = 'arrow.clockwise',
    this.onPrimaryAction,
    this.primaryLoading = false,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.secondaryActionSfSymbol,
    this.onSecondaryAction,
    this.footer,
    this.compact = false,
  });

  const TpStateCard.error({
    super.key,
    this.icon = TpIcons.alertCircle,
    required this.title,
    this.message,
    this.tone = TpStateTone.danger,
    this.primaryActionLabel = '重试',
    this.primaryActionIcon = TpIcons.refresh,
    this.primaryActionSfSymbol = 'arrow.clockwise',
    this.onPrimaryAction,
    this.primaryLoading = false,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.secondaryActionSfSymbol,
    this.onSecondaryAction,
    this.footer,
    this.compact = false,
  });

  const TpStateCard.prerequisite({
    super.key,
    this.icon = TpIcons.linkedAccounts,
    required this.title,
    this.message,
    this.tone = TpStateTone.brand,
    this.primaryActionLabel,
    this.primaryActionIcon = TpIcons.login,
    this.primaryActionSfSymbol = 'link',
    this.onPrimaryAction,
    this.primaryLoading = false,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.secondaryActionSfSymbol,
    this.onSecondaryAction,
    this.footer,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final TpStateTone tone;
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;
  final String? primaryActionSfSymbol;
  final VoidCallback? onPrimaryAction;
  final bool primaryLoading;
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final String? secondaryActionSfSymbol;
  final VoidCallback? onSecondaryAction;
  final Widget? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final density = context.tpDensity;
    final (iconFg, iconBg) = _resolveTone(colors);
    final hasPrimary =
        primaryActionLabel != null && primaryActionLabel!.isNotEmpty;
    final hasSecondary =
        secondaryActionLabel != null && secondaryActionLabel!.isNotEmpty;
    final verticalPad = compact
        ? density.cardPaddingVertical + TpTokens.space1
        : density.cardPaddingVertical + TpTokens.space4;

    return TpCard(
      padding: EdgeInsets.symmetric(
        horizontal: density.cardPaddingHorizontal + TpTokens.space2,
        vertical: verticalPad,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(TpTokens.radiusM),
            ),
            child: Icon(icon, size: TpTokens.iconL, color: iconFg),
          ),
          const SizedBox(height: TpTokens.space3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TpTypography.cardTitle(colors),
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: TpTokens.space1 + 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: TpTypography.itemMeta(colors),
              ),
            ),
          ],
          if (hasPrimary) ...[
            const SizedBox(height: TpTokens.space4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: AdaptiveButton(
                onPressed: onPrimaryAction,
                loading: primaryLoading,
                icon: primaryActionIcon ?? TpIcons.refresh,
                sfSymbol: primaryActionSfSymbol ?? 'arrow.clockwise',
                label: primaryActionLabel,
                height: 44,
                role: AdaptiveButtonRole.prominent,
              ),
            ),
          ],
          if (hasSecondary) ...[
            SizedBox(height: hasPrimary ? TpTokens.space2 : TpTokens.space3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: AdaptiveButton(
                onPressed: onSecondaryAction,
                icon: secondaryActionIcon ?? TpIcons.chevronRight,
                sfSymbol: secondaryActionSfSymbol ?? 'chevron.right',
                label: secondaryActionLabel,
                height: 44,
                role: AdaptiveButtonRole.plain,
              ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: TpTokens.space3),
            footer!,
          ],
        ],
      ),
    );
  }

  (Color, Color) _resolveTone(TpColors colors) {
    final alpha = colors.isDark ? 0.16 : 0.10;
    return switch (tone) {
      TpStateTone.neutral => (colors.textMuted, colors.surfaceSubtle),
      TpStateTone.brand => (colors.brandInk, colors.brandSoft),
      TpStateTone.warning => (
          colors.warningAmber,
          colors.warningAmber.withValues(alpha: alpha),
        ),
      TpStateTone.danger => (
          colors.dangerRed,
          colors.dangerRed.withValues(alpha: alpha),
        ),
      TpStateTone.success => (
          colors.successGreen,
          colors.successGreen.withValues(alpha: alpha),
        ),
    };
  }
}
