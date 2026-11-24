import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../utils/motion.dart';

/// Tactile press-down micro-scale with spring rebound, inspired by Telegram
/// iOS's responsive touch feel.
///
/// Uses a passive [Listener] so it never competes with inner [InkWell],
/// [GestureDetector], or scrollable drag gestures. Automatically cancels the
/// press scale if the pointer drifts beyond [kTouchSlop] (e.g. when scrolling)
/// and becomes a no-op when reduced motion is enabled.
class TpPressScale extends StatefulWidget {
  const TpPressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.97,
    this.enabled = true,
  });

  final Widget child;
  final double pressedScale;
  final bool enabled;

  @override
  State<TpPressScale> createState() => _TpPressScaleState();
}

class _TpPressScaleState extends State<TpPressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale;
  int? _activePointer;
  Offset? _downPosition;
  bool _pressed = false;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController.unbounded(vsync: this, value: 1.0);
  }

  @override
  void didUpdateWidget(covariant TpPressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) {
      _release();
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _reduceMotion || _activePointer != null) return;
    // Ignore secondary/right mouse clicks.
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _activePointer = event.pointer;
    _downPosition = event.position;
    _pressed = true;
    unawaited(
      _scale.animateTo(
        widget.pressedScale,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pressed || event.pointer != _activePointer || _downPosition == null) {
      return;
    }
    if ((event.position - _downPosition!).distance > kTouchSlop) {
      _release();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _release();
  }

  void _release() {
    _activePointer = null;
    _downPosition = null;
    if (!_pressed) return;
    _pressed = false;
    if (!mounted) return;
    if (_reduceMotion) {
      _scale.value = 1.0;
      return;
    }
    unawaited(
      _scale
          .animateWith(
            SpringSimulation(TgMotion.tactileSpring, _scale.value, 1.0, 0),
          )
          .whenComplete(() {
        if (mounted && !_pressed) _scale.value = 1.0;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _reduceMotion) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          final value = _scale.value;
          final scale = (value - 1.0).abs() < 1e-4 ? 1.0 : value;
          return Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
