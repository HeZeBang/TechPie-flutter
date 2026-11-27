import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../utils/platform.dart';
import 'tp_press_scale.dart';

/// Visual interaction role determining iOS/cross-platform tap highlight and
/// tactile press-scale behavior in [TpTapSurface].
enum TpTapFeedbackStyle {
  /// Grouped list rows (`TpListRow`, `TpAccentRow`, `TpProgressRow`).
  /// Uses a clean iOS table-cell press fill with no scale transform so adjacent
  /// rows keep aligned edges.
  row,

  /// Interactive cards (`TpCard`). Uses subtle spring scale plus a crisp
  /// foreground press scrim.
  card,

  /// Quick-action tiles (`TpFeatureGrid`). Uses spring scale plus a rounded
  /// tile fill.
  tile,

  /// Chrome and pill/circle action buttons. Uses spring scale plus a foreground
  /// press scrim.
  button,
}

/// Platform-authentic tappable surface for TechPie design system primitives.
///
/// - **iOS**: suppresses Android Material ripples (`NoSplash.splashFactory`),
///   delays the press fill briefly (~42 ms) during `pointerDown` so scroll
///   gestures don't flicker, clears immediately past [kTouchSlop], and shows a
///   short (~80 ms) full-highlight flash before fading smoothly on confirmed
///   quick taps — with zero `dart:async Timer` allocations.
/// - **Android / Desktop**: keeps crisp hover feedback, subtle brand splash,
///   and higher-contrast highlight states alongside tactile [TpPressScale]
///   for cards, tiles, and buttons.
class TpTapSurface extends StatefulWidget {
  const TpTapSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.style = TpTapFeedbackStyle.row,
    this.borderRadius,
    this.customBorder,
    this.pressedColor,
    this.enablePressScale = true,
    this.pressedScale,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final TpTapFeedbackStyle style;
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;
  final Color? pressedColor;
  final bool enablePressScale;
  final double? pressedScale;

  @override
  State<TpTapSurface> createState() => _TpTapSurfaceState();
}

class _TpTapSurfaceState extends State<TpTapSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _highlight;
  bool _fadingOut = false;
  int? _activePointer;
  Offset? _downPosition;
  bool _dragged = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  double get _resolvedScale =>
      widget.pressedScale ??
      switch (widget.style) {
        TpTapFeedbackStyle.row => 1.0,
        TpTapFeedbackStyle.card => 0.98,
        TpTapFeedbackStyle.tile => 0.95,
        TpTapFeedbackStyle.button => 0.95,
      };

  @override
  void initState() {
    super.initState();
    _highlight = AnimationController(vsync: this, value: 0.0);
  }

  @override
  void didUpdateWidget(covariant TpTapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_interactive && _highlight.value > 0) {
      _resetPointer();
      _fadingOut = false;
      _highlight.value = 0.0;
    }
  }

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  void _resetPointer() {
    _activePointer = null;
    _downPosition = null;
    _dragged = false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_interactive || _activePointer != null) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _activePointer = event.pointer;
    _downPosition = event.position;
    _dragged = false;
    _fadingOut = false;
    if (_reduceMotion) {
      _highlight.value = 1.0;
    } else {
      unawaited(
        _highlight.animateTo(
          1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.linear,
        ),
      );
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _dragged || _downPosition == null) {
      return;
    }
    if ((event.position - _downPosition!).distance > kTouchSlop) {
      _dragged = true;
      _fadingOut = false;
      _highlight.value = 0.0;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    final wasDragged = _dragged;
    _resetPointer();
    if (wasDragged || !mounted) {
      _fadingOut = false;
      _highlight.value = 0.0;
      return;
    }
    if (_reduceMotion) {
      _fadingOut = false;
      _highlight.value = 0.0;
      return;
    }
    _fadingOut = true;
    _highlight.value = 1.0;
    unawaited(
      _highlight.animateTo(
        0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.linear,
      ),
    );
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _resetPointer();
    _fadingOut = false;
    if (_reduceMotion) {
      _highlight.value = 0.0;
    } else {
      unawaited(
        _highlight.animateTo(
          0.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  Color? _overlayFor(TpColors colors, double t) {
    if (t <= 0.0) return null;
    return switch (widget.style) {
      TpTapFeedbackStyle.row =>
        (widget.pressedColor ?? colors.surfacePressed)
            .withValues(alpha: (colors.isDark ? 0.88 : 0.90) * t),
      TpTapFeedbackStyle.tile =>
        (widget.pressedColor ?? colors.surfacePressed)
            .withValues(alpha: (colors.isDark ? 0.72 : 0.78) * t),
      TpTapFeedbackStyle.card =>
        (widget.pressedColor ??
                (colors.isDark ? Colors.white : Colors.black))
            .withValues(alpha: (colors.isDark ? 0.08 : 0.06) * t),
      TpTapFeedbackStyle.button =>
        (widget.pressedColor ??
                (colors.isDark ? Colors.white : Colors.black))
            .withValues(
              alpha: (widget.pressedColor != null
                      ? 0.22
                      : (colors.isDark ? 0.14 : 0.09)) *
                  t,
            ),
    };
  }

  Decoration _decorationFor(Color? color) {
    if (widget.customBorder != null) {
      return ShapeDecoration(
        color: color,
        shape: widget.customBorder!,
      );
    }
    return BoxDecoration(
      color: color,
      borderRadius: widget.borderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_interactive) return widget.child;

    final colors = context.tpColors;
    final ios = isIos();
    final shouldScale =
        widget.enablePressScale && widget.style != TpTapFeedbackStyle.row;

    Widget content;
    if (ios) {
      final isForeground = widget.style == TpTapFeedbackStyle.card ||
          widget.style == TpTapFeedbackStyle.button;
      final highlighted = AnimatedBuilder(
        animation: _highlight,
        builder: (context, child) {
          final v = _highlight.value;
          final double t;
          if (v <= 0.0) {
            t = 0.0;
          } else if (_reduceMotion) {
            t = v;
          } else if (_fadingOut) {
            t = 1.0 -
                const Interval(0.36, 1.0, curve: Curves.easeOut)
                    .transform(1.0 - v);
          } else {
            t = const Interval(0.35, 1.0, curve: Curves.easeOut).transform(v);
          }
          final color = _overlayFor(colors, t);
          if (color == null) return child!;
          return DecoratedBox(
            position: isForeground
                ? DecorationPosition.foreground
                : DecorationPosition.background,
            decoration: _decorationFor(color),
            child: child,
          );
        },
        child: widget.child,
      );

      content = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: widget.borderRadius,
          customBorder: widget.customBorder,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: colors.textPrimary.withValues(
            alpha: colors.isDark ? 0.06 : 0.04,
          ),
          child: highlighted,
        ),
      );
    } else {
      content = InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: widget.borderRadius,
        customBorder: widget.customBorder,
        hoverColor: colors.textPrimary.withValues(
          alpha: colors.isDark ? 0.06 : 0.04,
        ),
        splashColor: colors.brandSoft,
        highlightColor: widget.pressedColor ??
            colors.surfacePressed.withValues(
              alpha: colors.isDark ? 0.62 : 0.68,
            ),
        child: widget.child,
      );
    }

    if (!shouldScale) return content;
    return TpPressScale(
      pressedScale: _resolvedScale,
      child: content,
    );
  }
}
