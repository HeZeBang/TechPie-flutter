import 'dart:ui';

import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.dart';

bool gpReduceTransparencyActive(BuildContext context) =>
    MediaQuery.maybeOf(context)?.highContrast ?? false;

/// Navigation/control glass per Part A §4. Content surfaces never use this.
final class GpGlass extends StatelessWidget {
  const GpGlass({super.key, required this.child, this.borderRadius});

  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.gpColors;
    final platform = Theme.of(context).platform;
    final apple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final reduceTransparency = gpReduceTransparencyActive(context);
    final fallback =
        colors.isDark ? colors.surfaceRaised : GpTokens.glassFallbackLight;
    final base = reduceTransparency
        ? fallback
        : colors.surface.withValues(alpha: apple ? 0.58 : 0.76);
    final tint =
        colors.isDark ? GpTokens.glassTintDark : GpTokens.glassTintLight;
    final highlightOpacity = reduceTransparency
        ? GpTokens.glassFallbackHighlightOpacity
        : GpTokens.glassHighlightOpacity;
    final surface = Container(
      decoration: BoxDecoration(
        color: reduceTransparency ? base.withValues(alpha: 1) : base,
        borderRadius: borderRadius,
        border: Border.all(
          color: apple && !reduceTransparency
              ? Colors.white.withValues(alpha: colors.isDark ? 0.16 : 0.48)
              : colors.border.withValues(alpha: 0.72),
        ),
        boxShadow: GpTokens.elevation2(colors.isDark),
      ),
      child: Stack(
        children: [
          DecoratedBox(
            key: Key(apple ? 'gp-liquid-glass-tint' : 'gp-android-blur-tint'),
            decoration: BoxDecoration(
              color: tint,
              gradient: apple && !reduceTransparency
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(
                          alpha: colors.isDark ? 0.13 : 0.30,
                        ),
                        Colors.white.withValues(
                          alpha: colors.isDark ? 0.02 : 0.05,
                        ),
                        colors.surface.withValues(alpha: 0.12),
                      ],
                      stops: const [0, 0.52, 1],
                    )
                  : null,
              borderRadius: borderRadius,
            ),
            child: child,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 1,
            child: Container(
              color: Colors.white.withValues(alpha: highlightOpacity),
            ),
          ),
        ],
      ),
    );

    Widget result = surface;
    if (!reduceTransparency && borderRadius == null) {
      result = ClipRect(
        child: BackdropFilter(
          key: Key(apple ? 'gp-liquid-glass-blur' : 'gp-android-glass-blur'),
          filter: ImageFilter.blur(
            sigmaX: apple ? 28 : 18,
            sigmaY: apple ? 28 : 18,
          ),
          child: result,
        ),
      );
    } else if (!reduceTransparency) {
      result = ClipRRect(
        borderRadius: borderRadius!,
        child: BackdropFilter(
          key: Key(apple ? 'gp-liquid-glass-blur' : 'gp-android-glass-blur'),
          filter: ImageFilter.blur(
            sigmaX: apple ? 28 : 18,
            sigmaY: apple ? 28 : 18,
          ),
          child: result,
        ),
      );
    }
    return result;
  }
}
