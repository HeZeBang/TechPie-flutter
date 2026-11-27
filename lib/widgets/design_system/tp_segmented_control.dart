import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../theme/theme.dart';
import '../../utils/adaptive_motion.dart';
import '../../utils/haptics.dart';
import '../../utils/motion.dart';

/// Unified spring-animated segmented control for TechPie across all platforms.
class TpSegmentedControl extends StatefulWidget {
  const TpSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.enabled = true,
    this.shrinkWrap = false,
    this.height,
    this.semanticLabel,
  });

  final int value;
  final List<String> segments;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final bool shrinkWrap;
  final double? height;
  final String? semanticLabel;

  @override
  State<TpSegmentedControl> createState() => _TpSegmentedControlState();
}

class _TpSegmentedControlState extends State<TpSegmentedControl>
    with SingleTickerProviderStateMixin {
  static const double _trackPadding = 3.0;

  late final AnimationController _thumbT = AnimationController.unbounded(
    vsync: this,
    value: _clampedIndex(widget.value, widget.segments.length).toDouble(),
  );

  static int _clampedIndex(int value, int length) {
    if (length <= 1) return 0;
    return value.clamp(0, length - 1);
  }

  @override
  void didUpdateWidget(covariant TpSegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTarget =
        _clampedIndex(oldWidget.value, oldWidget.segments.length).toDouble();
    final newTarget =
        _clampedIndex(widget.value, widget.segments.length).toDouble();

    if (widget.segments.length != oldWidget.segments.length) {
      _thumbT.value = newTarget;
      return;
    }

    if (oldTarget != newTarget) {
      final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduceMotion) {
        _thumbT.value = newTarget;
      } else {
        unawaited(
          _thumbT.animateWith(
            SpringSimulation(
              TgMotion.snappySpring,
              _thumbT.value,
              newTarget,
              0,
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _thumbT.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (!widget.enabled) return;
    final selected = _clampedIndex(widget.value, widget.segments.length);
    if (index == selected) return;
    unawaited(AppHaptics.play(AppHaptics.selection));
    widget.onChanged(index);
  }

  double _measureMaxLabelWidth(BuildContext context, TextStyle style) {
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final scaler = MediaQuery.textScalerOf(context);
    var maxWidth = 0.0;
    for (final label in widget.segments) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > maxWidth) {
        maxWidth = painter.width;
      }
      painter.dispose();
    }
    return maxWidth;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.segments.length;
    if (count == 0) return const SizedBox.shrink();

    final colors = context.tpColors;
    final selectedIndex = _clampedIndex(widget.value, count);
    final resolvedHeight =
        widget.height ?? (context.tpDensity.isCompact ? 36.0 : 38.0);
    final outerRadius = BorderRadius.circular(TpTokens.radiusS);
    final innerRadius = BorderRadius.circular(TpTokens.radiusS - _trackPadding);

    final trackColor =
        colors.textPrimary.withValues(alpha: colors.isDark ? 0.08 : 0.065);
    final trackBorder = colors.isDark
        ? Border.all(color: colors.border)
        : Border.all(color: colors.divider, width: 0.5);
    final thumbColor =
        colors.isDark ? colors.opaqueBrandContainer : colors.surface;
    final thumbBorder = Border.all(
      color: colors.brand.withValues(alpha: colors.isDark ? 0.38 : 0.16),
      width: 0.75,
    );
    final thumbShadows = colors.isDark
        ? null
        : [
            BoxShadow(
              color: colors.textPrimary.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 1.5),
            ),
          ];

    final selectedTextStyle = TpTypography.badge(colors.brandInk).copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    );
    final unselectedTextStyle = TpTypography.badge(colors.textMuted).copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
    );
    final hoverColor =
        colors.textPrimary.withValues(alpha: colors.isDark ? 0.06 : 0.04);
    final highlightColor = colors.textPrimary.withValues(alpha: 0.06);

    return Semantics(
      container: true,
      label: widget.semanticLabel,
      enabled: widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.45,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedWidth = constraints.hasBoundedWidth;
            final double innerWidth;
            if (widget.shrinkWrap || !hasBoundedWidth) {
              final maxLabelWidth =
                  _measureMaxLabelWidth(context, selectedTextStyle);
              final naturalSegmentWidth =
                  (maxLabelWidth + 28.0).clamp(64.0, 220.0);
              final naturalInnerWidth = naturalSegmentWidth * count;
              innerWidth = hasBoundedWidth
                  ? math.min(
                      naturalInnerWidth,
                      math.max(0.0, constraints.maxWidth - _trackPadding * 2),
                    )
                  : naturalInnerWidth;
            } else {
              innerWidth =
                  math.max(0.0, constraints.maxWidth - _trackPadding * 2);
            }

            final segmentWidth = innerWidth / count;

            final track = Container(
              width: innerWidth + _trackPadding * 2,
              height: resolvedHeight,
              padding: const EdgeInsets.all(_trackPadding),
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: outerRadius,
                border: trackBorder,
              ),
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _thumbT,
                    builder: (context, child) {
                      final clamped =
                          _thumbT.value.clamp(0.0, (count - 1).toDouble());
                      return PositionedDirectional(
                        start: clamped * segmentWidth,
                        top: 0,
                        bottom: 0,
                        width: segmentWidth,
                        child: IgnorePointer(child: child),
                      );
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: innerRadius,
                        border: thumbBorder,
                        boxShadow: thumbShadows,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < count; index++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: index == selectedIndex,
                            child: Material(
                              type: MaterialType.transparency,
                              shape: RoundedRectangleBorder(
                                borderRadius: innerRadius,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: widget.enabled
                                    ? () => _select(index)
                                    : null,
                                hoverColor: hoverColor,
                                highlightColor: highlightColor,
                                splashFactory: NoSplash.splashFactory,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: AnimatedDefaultTextStyle(
                                      duration: appAnimationDuration(
                                        context,
                                        TgMotion.fast,
                                      ),
                                      curve: TgMotion.easeOutQuint,
                                      style: index == selectedIndex
                                          ? selectedTextStyle
                                          : unselectedTextStyle,
                                      child: Text(
                                        widget.segments[index],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );

            if (widget.shrinkWrap && hasBoundedWidth) {
              return Center(child: track);
            }
            return track;
          },
        ),
      ),
    );
  }
}
