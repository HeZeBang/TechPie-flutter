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
/// Tapping anywhere on the card (except the balance visibility toggle) opens the
/// payment QR code directly; card details and full transaction history are
/// accessed from inside the payment-code page.
///
/// - Compact mode (`expandedCard: false`, mobile/narrow): slim single-row card
///   with a mini entity-card thumbnail, cached balance (with an enlarged-hit-area
///   eye visibility toggle), and a lightweight QR entry indicator.
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
    this.hideBalance = false,
    this.onToggleHideBalance,
    required this.onOpenPayCode,
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
  final bool hideBalance;
  final VoidCallback? onToggleHideBalance;
  final VoidCallback onOpenPayCode;
  final bool expandedCard;

  @override
  Widget build(BuildContext context) {
    return expandedCard
        ? _buildExpandedEntityCard(context)
        : _buildCompactStrip(context);
  }

  Widget _buildExpandedEntityCard(BuildContext context) {
    final colors = context.tpColors;
    final canToggleBalance = configured && onToggleHideBalance != null;
    final String primaryValue;
    final String eyebrow;
    if (!configured) {
      eyebrow = '校园一卡通';
      primaryValue = '点击绑定';
    } else if (hideBalance) {
      eyebrow = '余额';
      primaryValue = '••••';
    } else if (balanceText != null && balanceText!.isNotEmpty) {
      eyebrow = '余额';
      primaryValue = balanceText!;
    } else {
      eyebrow = '校园一卡通';
      primaryValue = '点击亮码';
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
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        eyebrow,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize:
                                              (11 * scale).clamp(11.0, 12.5),
                                          fontWeight: FontWeight.w600,
                                          color: _cardMutedInk,
                                          fontFamilyFallback:
                                              TpTypography.fontFamilyFallback,
                                        ),
                                      ),
                                      if (canToggleBalance)
                                        _BalanceEyeButton(
                                          hidden: hideBalance,
                                          color: _cardMutedInk,
                                          iconSize:
                                              (14 * scale).clamp(13.5, 16.0),
                                          hitSize: 36,
                                          onTap: onToggleHideBalance!,
                                        ),
                                    ],
                                  ),
                                  if (!canToggleBalance)
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
                            _PayIndicator(
                              configured: configured,
                              foregroundColor: configured
                                  ? _cardPayButtonBg
                                  : _cardMutedInk,
                              backgroundColor: (configured
                                      ? _cardPayButtonBg
                                      : _cardMutedInk)
                                  .withValues(alpha: 0.10),
                              iconSize: (TpTokens.iconXs * scale)
                                  .clamp(13.5, 16.0),
                              fontSize: (11.5 * scale).clamp(11.0, 13.0),
                              padding: EdgeInsets.symmetric(
                                horizontal: (10 * scale).clamp(10.0, 12.0),
                                vertical: (5 * scale).clamp(5.0, 6.0),
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
        onTap: onOpenPayCode,
        enablePressScale: false,
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
    final canToggleBalance = configured && onToggleHideBalance != null;

    final String subtitle;
    if (!configured) {
      subtitle = '绑定后可一键亮码与查看余额';
    } else if (hideBalance) {
      subtitle = '余额 ••••';
    } else if (balanceText != null && balanceText!.isNotEmpty) {
      subtitle = '余额 $balanceText';
    } else {
      subtitle = '点击亮码';
    }

    return TpPressScale(
      pressedScale: 0.98,
      child: TpCard(
        key: const ValueKey('home.campus-card-strip'),
        onTap: onOpenPayCode,
        enablePressScale: false,
        padding: const EdgeInsets.symmetric(
          horizontal: TpTokens.cardPaddingHorizontal,
          vertical: TpTokens.space1,
        ),
        child: Row(
          children: [
            // Mini entity campus-card thumbnail composed cleanly with zero
            // white-corner bleed in dark mode.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: TpTokens.space2),
              child: Container(
                key: const ValueKey('home.campus-card-mini-thumb'),
                width: 54,
                height: 34,
                decoration: BoxDecoration(
                  color: _cardBodyCanvas,
                  borderRadius: BorderRadius.circular(TpTokens.radiusXs),
                  border: Border.all(
                    color: colors.isDark ? colors.border : colors.divider,
                    width: 0.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: colors.isDark ? 0.30 : 0.10,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 34,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFB5101F), Color(0xFF8C0813)],
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 14,
                          height: 2,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.72),
                            borderRadius:
                                BorderRadius.circular(TpTokens.radiusBar),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 66,
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
            ),
            const SizedBox(width: TpTokens.space3),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: TpTokens.space2,
                        bottom: canToggleBalance ? 10 : TpTokens.space2,
                      ),
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
                              color: configured && !hideBalance
                                  ? colors.textSecondary
                                  : colors.textMuted,
                              fontWeight: configured && !hideBalance
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (canToggleBalance)
                    _BalanceEyeButton(
                      hidden: hideBalance,
                      color: colors.textMuted,
                      iconSize: 14,
                      hitSize: 38,
                      onTap: onToggleHideBalance!,
                    ),
                ],
              ),
            ),
            const SizedBox(width: TpTokens.space2),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: TpTokens.space2),
              child: _PayIndicator(
                configured: configured,
                foregroundColor:
                    configured ? colors.brandInk : colors.textMuted,
                backgroundColor:
                    configured ? colors.brandSoft : colors.surfaceSubtle,
                iconSize: TpTokens.iconXs,
                fontSize: 11.5,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Passive visual affordance communicating that tapping the card opens the QR
/// payment code, without introducing a competing nested tap target.
class _PayIndicator extends StatelessWidget {
  const _PayIndicator({
    required this.configured,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.iconSize,
    required this.fontSize,
    required this.padding,
  });

  final bool configured;
  final Color foregroundColor;
  final Color backgroundColor;
  final double iconSize;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('home.campus-card-pay'),
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(TpTokens.radiusPill),
        border: Border.all(
          color: foregroundColor.withValues(alpha: 0.14),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            TpIcons.qrCode,
            size: iconSize,
            color: foregroundColor,
          ),
          const SizedBox(width: 4),
          Text(
            configured ? '亮码' : '进入',
            style: TpTypography.badge(foregroundColor).copyWith(
              fontSize: fontSize,
            ),
          ),
          const SizedBox(width: 1),
          Icon(
            TpIcons.chevronRight,
            size: iconSize,
            color: foregroundColor,
          ),
        ],
      ),
    );
  }
}

class _BalanceEyeButton extends StatelessWidget {
  const _BalanceEyeButton({
    required this.hidden,
    required this.color,
    required this.iconSize,
    required this.hitSize,
    required this.onTap,
  });

  final bool hidden;
  final Color color;
  final double iconSize;
  final double hitSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = hidden ? '显示余额' : '隐藏余额';
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TpTokens.radiusS),
    );
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('home.campus-card-balance-toggle'),
            onTap: onTap,
            customBorder: shape,
            hoverColor: color.withValues(alpha: 0.10),
            splashColor: color.withValues(alpha: 0.16),
            child: SizedBox.square(
              dimension: hitSize,
              child: Center(
                child: Icon(
                  hidden ? TpIcons.eyeOff : TpIcons.eye,
                  size: iconSize,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
