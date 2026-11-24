import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_icons.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';
import 'tp_card.dart';
import 'tp_press_scale.dart';

/// Responsive campus-card entry on Home.
///
/// - Compact mode (`expandedCard: false`, mobile/narrow): slim single-row card
///   with a mini entity-card thumbnail, cached balance, and one-tap pay button.
/// - Expanded mode (`expandedCard: true`, wide Bento column): authentic
///   ShanghaiTech skyline entity card surface (`card-full.png`) mirroring the
///   TechPie website showcase, with fixed high-contrast card-face inks.
class TpCampusCardStrip extends StatelessWidget {
  const TpCampusCardStrip({
    super.key,
    required this.configured,
    required this.balanceText,
    required this.maskPersonalInfo,
    required this.onOpenPayCode,
    required this.onOpenCard,
    this.expandedCard = false,
  });

  static const String cardFaceAsset = 'assets/campus_card/images/card-full.png';
  static const Color _cardHeaderFallback = Color(0xFF960B15);
  static const Color _cardBodyFallback = Color(0xFFFAF3F4);
  static const Color _cardBalanceInk = Color(0xFF7A1018);
  static const Color _cardMutedInk = Color(0xFF9E4B52);
  static const Color _cardPayButtonBg = Color(0xFFA30B19);

  final bool configured;
  final String? balanceText;
  final bool maskPersonalInfo;
  final VoidCallback onOpenPayCode;
  final VoidCallback onOpenCard;
  final bool expandedCard;

  @override
  Widget build(BuildContext context) {
    return expandedCard
        ? _buildExpandedEntityCard(context)
        : _buildCompactStrip(context);
  }

  Widget _buildExpandedEntityCard(BuildContext context) {
    final colors = context.tpColors;
    final String primaryValue;
    final String eyebrow;
    if (!configured) {
      eyebrow = '校园一卡通';
      primaryValue = '点击绑定';
    } else if (maskPersonalInfo) {
      eyebrow = '余额';
      primaryValue = '••••';
    } else if (balanceText != null && balanceText!.isNotEmpty) {
      eyebrow = '余额';
      primaryValue = balanceText!;
    } else {
      eyebrow = '校园一卡通';
      primaryValue = '查看余额';
    }

    return TpPressScale(
      pressedScale: 0.985,
      child: TpCard(
        key: const ValueKey('home.campus-card-strip'),
        borderColor: colors.isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.06),
        onTap: onOpenCard,
        child: SizedBox(
          height: 156,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Official ShanghaiTech crimson-top skyline card face.
              Image.asset(
                cardFaceAsset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => const Column(
                  children: [
                    Expanded(
                      flex: 32,
                      child: ColoredBox(color: _cardHeaderFallback),
                    ),
                    Expanded(
                      flex: 68,
                      child: ColoredBox(color: _cardBodyFallback),
                    ),
                  ],
                ),
              ),
              // Subtle gradient over bottom half for razor-sharp text contrast.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.38, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Crimson header band
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TpTokens.cardPaddingHorizontal,
                      11,
                      TpTokens.cardPaddingHorizontal,
                      8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '上海科技大学',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                  color: Colors.white,
                                  fontFamilyFallback:
                                      TpTypography.fontFamilyFallback,
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                'SHANGHAITECH · CAMPUS CARD',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.6,
                                  height: 1.2,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: TpTokens.space2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(
                              TpTokens.radiusPill,
                            ),
                          ),
                          child: const Text(
                            '校园卡',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontFamilyFallback:
                                  TpTypography.fontFamilyFallback,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Bottom balance + quick pay CTA
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TpTokens.cardPaddingHorizontal,
                      TpTokens.space2,
                      TpTokens.cardPaddingHorizontal,
                      14,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                eyebrow,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _cardMutedInk,
                                  fontFamilyFallback:
                                      TpTypography.fontFamilyFallback,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                primaryValue,
                                key: const ValueKey(
                                  'home.campus-card-entity-balance',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                  letterSpacing: -0.4,
                                  color: _cardBalanceInk,
                                  fontFeatures: TpTypography.tabularFigures,
                                  fontFamilyFallback:
                                      TpTypography.fontFamilyFallback,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: TpTokens.space2),
                        TpPressScale(
                          pressedScale: 0.94,
                          child: Material(
                            color: _cardPayButtonBg,
                            borderRadius: BorderRadius.circular(
                              TpTokens.radiusPill,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: const ValueKey('home.campus-card-pay'),
                              onTap: onOpenPayCode,
                              hoverColor: Colors.white.withValues(alpha: 0.14),
                              highlightColor:
                                  Colors.white.withValues(alpha: 0.18),
                              splashColor: Colors.white.withValues(alpha: 0.24),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      TpIcons.qrCode,
                                      size: TpTokens.iconXs,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      configured ? '亮码' : '进入',
                                      style: TpTypography.badge(Colors.white),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStrip(BuildContext context) {
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
            // Mini entity campus-card thumbnail replacing generic icon tile.
            Container(
              key: const ValueKey('home.campus-card-mini-thumb'),
              width: 48,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TpTokens.radiusXs),
                border: Border.all(
                  color: colors.isDark ? colors.border : colors.divider,
                  width: 0.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                cardFaceAsset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: colors.opaqueBrandContainer,
                  child: Icon(
                    TpIcons.campusCard,
                    size: TpTokens.iconS,
                    color: colors.brandInk,
                  ),
                ),
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
                    style: TpTypography.itemMeta(colors).copyWith(
                      color: configured && !maskPersonalInfo
                          ? colors.textSecondary
                          : colors.textMuted,
                      fontWeight: configured && !maskPersonalInfo
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
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
