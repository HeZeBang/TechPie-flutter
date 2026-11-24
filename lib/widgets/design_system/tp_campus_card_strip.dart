import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_icons.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';
import 'tp_card.dart';
import 'tp_press_scale.dart';

/// Compact campus-card quick strip on Home showing cached balance (respecting
/// privacy blur) and a one-tap payment code button.
class TpCampusCardStrip extends StatelessWidget {
  const TpCampusCardStrip({
    super.key,
    required this.configured,
    required this.balanceText,
    required this.maskPersonalInfo,
    required this.onOpenPayCode,
    required this.onOpenCard,
  });

  final bool configured;
  final String? balanceText;
  final bool maskPersonalInfo;
  final VoidCallback onOpenPayCode;
  final VoidCallback onOpenCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;

    final String subtitle;
    if (!configured) {
      subtitle = '绑定后可一键亮码与查看余额';
    } else if (maskPersonalInfo) {
      subtitle = '余额 ••••';
    } else if (balanceText != null && balanceText!.isNotEmpty) {
      subtitle = '余额 $balanceText';
    } else {
      subtitle = '点击查看卡包与余额';
    }

    return TpPressScale(
      pressedScale: 0.98,
      child: TpCard(
        key: const ValueKey('home.campus-card-strip'),
        onTap: onOpenCard,
        padding: const EdgeInsets.symmetric(
          horizontal: TpTokens.cardPaddingHorizontal,
          vertical: TpTokens.space3,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.opaqueBrandContainer,
                borderRadius: BorderRadius.circular(TpTokens.radiusS),
              ),
              child: Icon(
                TpIcons.campusCard,
                size: TpTokens.iconM,
                color: colors.brandInk,
              ),
            ),
            const SizedBox(width: TpTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '校园卡',
                    style: TpTypography.itemTitle(colors),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TpTypography.itemMeta(colors),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: TpTokens.space2),
            TpPressScale(
              pressedScale: 0.94,
              child: Material(
                color: configured ? colors.brand : colors.opaqueBrandContainer,
                borderRadius: BorderRadius.circular(TpTokens.radiusPill),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('home.campus-card-pay'),
                  onTap: onOpenPayCode,
                  hoverColor: configured
                      ? colors.onBrand.withValues(alpha: 0.12)
                      : colors.textPrimary.withValues(
                          alpha: colors.isDark ? 0.06 : 0.04,
                        ),
                  highlightColor: configured
                      ? colors.onBrand.withValues(alpha: 0.16)
                      : colors.textPrimary.withValues(alpha: 0.08),
                  splashColor: configured
                      ? colors.onBrand.withValues(alpha: 0.22)
                      : colors.brandSoft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TpTokens.space3,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          TpIcons.qrCode,
                          size: TpTokens.iconXs,
                          color: configured ? colors.onBrand : colors.brandInk,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          configured ? '亮码' : '进入',
                          style: TpTypography.badge(
                            configured ? colors.onBrand : colors.brandInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
