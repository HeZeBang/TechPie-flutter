import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../utils/platform.dart';

class SwipeAction {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  const SwipeAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });
}

/// MD3-styled swipeable list tile with custom drag tracking, emphasized
/// curves on release, and a fly-off + height-collapse + fade dismiss
/// sequence. Use as a Dismissible alternative when you need finer control
/// over the motion.
///
/// - Right swipe past [threshold] (or with strong velocity) calls
///   [onStartSwipe] and springs back. The child stays mounted.
/// - Left swipe past [threshold] (or with strong velocity) awaits
///   [confirmEndSwipe] (e.g. snackbar undo). On `true`, the card flies
///   off screen, collapses its height, fades out, then [onDismissed]
///   fires — at which point the parent should remove the entry from
///   the underlying list.
class SwipeableCard extends StatefulWidget {
  const SwipeableCard({
    super.key,
    required this.child,
    this.startAction,
    this.endAction,
    this.onStartSwipe,
    this.onDismissed,
    this.enabled = true,
    this.threshold = 0.32,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.bottomMargin = 12,
  });

  final Widget child;
  final SwipeAction? startAction;
  final SwipeAction? endAction;

  final VoidCallback? onStartSwipe;
  // Fired once the card has finished its fly-off + collapse on a
  // left-swipe past [threshold]. Caller should remove the underlying
  // entry (and may show an undo affordance separately).
  final VoidCallback? onDismissed;

  final bool enabled;
  final double threshold;
  final BorderRadius borderRadius;
  final double bottomMargin;

  @override
  State<SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<SwipeableCard>
    with TickerProviderStateMixin {
  // MD3 motion curves.
  static const _emphasized = Cubic(0.2, 0, 0, 1);
  static const _emphasizedAccelerate = Cubic(0.3, 0, 0.8, 0.15);

  late final AnimationController _move = AnimationController.unbounded(
    vsync: this,
    value: 0,
  )..addListener(_onMove);

  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  double _width = 1;

  @override
  void dispose() {
    _move
      ..removeListener(_onMove)
      ..dispose();
    _collapse.dispose();
    super.dispose();
  }

  void _onMove() {
    if (mounted) setState(() {});
  }

  // Drag handlers ----------------------------------------------------

  void _onStart(DragStartDetails _) {
    _move.stop();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final dx = details.primaryDelta ?? 0;
    final next = _move.value + dx / _width;
    // Mild rubber-band beyond ±1.
    final clamped = next.clamp(-1.15, 1.15);
    _move.value = clamped;
  }

  Future<void> _onEnd(DragEndDetails details) async {
    final value = _move.value;
    final velocity = (details.primaryVelocity ?? 0) / _width;
    final magnitude = value.abs();
    final fast = velocity.abs() > 1.6 && magnitude > widget.threshold * 0.4;
    final shouldCommit = magnitude >= widget.threshold || fast;

    if (!shouldCommit) {
      await _springBack();
      return;
    }
    if (value > 0) {
      // Right swipe: fire-and-spring-back.
      widget.onStartSwipe?.call();
      await _springBack();
      return;
    }
    // Left swipe: animate out immediately. Caller may provide undo via
    // a SnackBar after [onDismissed] fires (commonly by un-doing the
    // underlying state mutation).
    if (widget.onDismissed == null) {
      await _springBack();
      return;
    }
    await _dismissToEnd();
  }

  Future<void> _dismissToEnd() async {
    await _flyOff(-1);
    if (!mounted) return;
    await _collapseDown();
    if (!mounted) return;
    widget.onDismissed!.call();
  }

  Future<void> _springBack() {
    if (_reduceMotion) {
      _move.value = 0;
      return Future<void>.value();
    }
    return _move.animateTo(
      0,
      duration: Duration(milliseconds: isIos() ? 250 : 280),
      curve: isIos() ? Curves.easeOut : _emphasized,
    );
  }

  Future<void> _flyOff(int sign) {
    if (_reduceMotion) {
      _move.value = sign * 1.25;
      return Future<void>.value();
    }
    return _move.animateTo(
      sign * 1.25,
      duration: Duration(milliseconds: isIos() ? 200 : 220),
      curve: isIos() ? Curves.easeIn : _emphasizedAccelerate,
    );
  }

  Future<void> _collapseDown() {
    if (_reduceMotion) {
      _collapse.value = 1;
      return Future<void>.value();
    }
    return _collapse.forward();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _collapse,
      builder: (context, child) {
        final t = _collapse.value;
        // Use Curves.easeInOutCubicEmphasized via direct curve evaluation.
        final eased = (isIos() ? Curves.easeInOut : _emphasized).transform(t);
        return ClipRect(
          child: Align(
            heightFactor: (1 - eased).clamp(0.0, 1.0),
            alignment: Alignment.topCenter,
            child: Opacity(
              opacity: (1 - eased).clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = constraints.maxWidth <= 0 ? 1 : constraints.maxWidth;
          final value = _move.value.clamp(-1.15, 1.15);
          final progress = value.abs().clamp(0.0, 1.0).toDouble();
          final showStart = value > 0 && widget.startAction != null;
          final showEnd = value < 0 && widget.endAction != null;
          final action = showStart
              ? widget.startAction
              : showEnd
                  ? widget.endAction
                  : null;

          return Padding(
            padding: EdgeInsets.only(bottom: widget.bottomMargin),
            child: Stack(
              children: [
                if (action != null)
                  Positioned.fill(
                    child: _SwipeReveal(
                      action: action,
                      progress: progress,
                      alignToEnd: showEnd,
                      borderRadius: widget.borderRadius,
                    ),
                  ),
                Transform.translate(
                  offset: Offset(value * _width * 0.92, 0),
                  child: Transform.scale(
                    scale: isIos() ? 1 : 1 - progress * 0.04,
                    alignment: Alignment.center,
                    child: Semantics(
                      customSemanticsActions: _semanticActions,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: _onStart,
                        onHorizontalDragUpdate: _onUpdate,
                        onHorizontalDragEnd: _onEnd,
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Map<CustomSemanticsAction, VoidCallback>? get _semanticActions {
    if (!widget.enabled) return null;
    final actions = <CustomSemanticsAction, VoidCallback>{};
    if (widget.startAction != null && widget.onStartSwipe != null) {
      actions[CustomSemanticsAction(label: widget.startAction!.label)] =
          widget.onStartSwipe!;
    }
    if (widget.endAction != null && widget.onDismissed != null) {
      actions[CustomSemanticsAction(label: widget.endAction!.label)] =
          () => unawaited(_dismissToEnd());
    }
    return actions.isEmpty ? null : actions;
  }
}

/// Animated entry wrapper that runs a height-expand + fade-in + slight
/// translate-in when first mounted. Pair with [SwipeableCard]'s exit
/// collapse so add/remove transitions are symmetric.
///
/// Uses MD3 emphasized-decelerate easing for the appearance, matching
/// the spec for "entering elements".
class CardEnterAnimation extends StatefulWidget {
  const CardEnterAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final Duration duration;

  @override
  State<CardEnterAnimation> createState() => _CardEnterAnimationState();
}

class _CardEnterAnimationState extends State<CardEnterAnimation>
    with SingleTickerProviderStateMixin {
  static const _emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      unawaited(_ctrl.forward());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _emphasizedDecelerate.transform(_ctrl.value);
        return ClipRect(
          child: Align(
            heightFactor: t.clamp(0.0, 1.0),
            alignment: Alignment.topCenter,
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * -8),
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _SwipeReveal extends StatelessWidget {
  const _SwipeReveal({
    required this.action,
    required this.progress,
    required this.alignToEnd,
    required this.borderRadius,
  });

  final SwipeAction action;
  final double progress;
  final bool alignToEnd;
  final BorderRadius borderRadius;

  static const _emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);

  @override
  Widget build(BuildContext context) {
    final eased = _emphasizedDecelerate.transform(progress.clamp(0.0, 1.0));
    final opacity = (eased * 1.2).clamp(0.0, 1.0);
    final iconScale = 0.7 + eased * 0.5;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: action.background,
        borderRadius: borderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Align(
          alignment: alignToEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: iconScale,
                  child: Icon(action.icon, color: action.foreground),
                ),
                const SizedBox(width: 8),
                Text(
                  action.label,
                  style: TextStyle(
                    color: action.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
