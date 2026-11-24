import 'dart:math' as math;

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
///   ShanghaiTech skyline entity card surface (`707:445` physical card ratio)
///   composed from the crimson header band and `card-bottom.png` skyline canvas
///   so resizing window width or height always fills cleanly top-to-bottom
///   without cropping the crimson band or skyline artwork.
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
  static const String cardBottomAsset =
      'assets/campus_card/images/card-bottom.png';
  static const double cardAspectRatio = 707 / 445;

  static const Color _cardHeaderCrimson = Color(0xFF9D0A12);
  static const Color _cardHeaderSeam = Color(0xFF84070E);
  static const Color _cardBodyCanvas = Color(0xFFFEF9F9);
  static const Color _cardBodyBlush = Color(0xFFFDEBEC);
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

    Widget buildCardSurface(double width, double height) {
      final scale = (width / 360).clamp(0.92, 1.22);
      final horizontalPadding = (16 * scale).clamp(14.0, 20.0);
      final headerHeight = math.max(54.0, height * 0.27);

      return SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top ShanghaiTech crimson band: fills full width & stays
            // proportionally locked to ~27% of card height so header text
            // never spills onto the light card body at any window size.
            Container(
              key: const ValueKey('home.campus-card-header-band'),
              height: headerHeight,
              decoration: const BoxDecoration(
                color: _cardHeaderCrimson,
                border: Border(
                  bottom: BorderSide(color: _cardHeaderSeam, width: 0.5),
                ),
              ),
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '上海科技大学',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5 * scale,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: Colors.white,
                            fontFamilyFallback: TpTypography.fontFamilyFallback,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'SHANGHAITECH · CAMPUS CARD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: (9.5 * scale).clamp(9.0, 11.0),
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
                    padding: EdgeInsets.symmetric(
                      horizontal: (8 * scale).clamp(8.0, 10.0),
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(TpTokens.radiusPill),
                    ),
                    child: Text(
                      '校园卡',
                      style: TextStyle(
                        fontSize: (10.5 * scale).clamp(10.0, 12.0),
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamilyFallback: TpTypography.fontFamilyFallback,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom skyline body: seamlessly fills all remaining vertical
            // space edge-to-edge with the exact card blush canvas.
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.65, 1.0],
                    colors: [_cardBodyCanvas, _cardBodyCanvas, _cardBodyBlush],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        cardBottomAsset,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        filterQuality: FilterQuality.high,
                        excludeFromSemantics: true,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    // Soft bottom legibility wash behind balance & pay CTA.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.48, 1.0],
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              _cardBodyCanvas.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          TpTokens.space2,
                          horizontalPadding,
                          (14 * scale).clamp(12.0, 18.0),
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
                                    style: TextStyle(
                                      fontSize: (11 * scale).clamp(11.0, 12.5),
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
                                    style: TextStyle(
                                      fontSize: (23 * scale).clamp(21.0, 28.0),
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
                                  hoverColor:
                                      Colors.white.withValues(alpha: 0.14),
                                  highlightColor:
                                      Colors.white.withValues(alpha: 0.18),
                                  splashColor:
                                      Colors.white.withValues(alpha: 0.24),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal:
                                          (14 * scale).clamp(13.0, 17.0),
                                      vertical: (8 * scale).clamp(7.5, 9.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          TpIcons.qrCode,
                                          size: (TpTokens.iconXs * scale)
                                              .clamp(13.5, 16.0),
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          configured ? '亮码' : '进入',
                                          style: TpTypography.badge(
                                            Colors.white,
                                          ).copyWith(
                                            fontSize:
                                                (11.5 * scale).clamp(11.0, 13.0),
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
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return TpPressScale(
      pressedScale: 0.985,
      child: TpCard(
        key: const ValueKey('home.campus-card-strip'),
        color: _cardBodyCanvas,
        borderColor: colors.isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.06),
        onTap: onOpenCard,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 360.0;
            final naturalHeight = width / cardAspectRatio;
            final height = constraints.hasTightHeight
                ? constraints.maxHeight
                : (constraints.hasBoundedHeight
                    ? math.min(naturalHeight, constraints.maxHeight)
                    : naturalHeight);
            return buildCardSurface(width, height);
          },
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
            // Mini entity campus-card thumbnail composed cleanly with zero
            // white-corner bleed in dark mode.
            Container(
              key: const ValueKey('home.campus-card-mini-thumb'),
              width: 48,
              height: 32,
              decoration: BoxDecoration(
                color: _cardBodyCanvas,
                borderRadius: BorderRadius.circular(TpTokens.radiusXs),
                border: Border.all(
                  color: colors.isDark ? colors.border : colors.divider,
                  width: 0.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(
                    flex: 28,
                    child: ColoredBox(color: _cardHeaderCrimson),
                  ),
                  Expanded(
                    flex: 72,
                    child: ColoredBox(
                      color: _cardBodyCanvas,
                      child: Image.asset(
                        cardBottomAsset,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: _cardBodyBlush,
                        ),
                      ),
                    ),
                  ),
                ],
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
