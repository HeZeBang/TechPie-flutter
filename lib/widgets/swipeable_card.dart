import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';

import '../utils/haptics.dart';
import '../utils/motion.dart';
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
  static const _emphasizedAccelerate = Cubic(0.3, 0, 0.8, 0.15);

  late final AnimationController _move = AnimationController.unbounded(
    vsync: this,
    value: 0,
  )..addListener(_onMove);

  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: TgMotion.medium,
  );

  late final AnimationController _revealBounce = AnimationController.unbounded(
    vsync: this,
    value: 1,
  )..addListener(_onMove);

  double _width = 1;
  bool _crossedThreshold = false;

  @override
  void dispose() {
    _move
      ..removeListener(_onMove)
      ..dispose();
    _revealBounce
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
    _crossedThreshold = false;
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final dx = details.primaryDelta ?? 0;
    final next = _move.value + dx / _width;
    // 1:1 tracking through the commit zone, with smooth asymptotic rubber-band
    // resistance beyond 0.85 so overscrolling feels elastic like Telegram iOS.
    final absNext = next.abs();
    final damped = absNext <= 0.85
        ? next
        : next.sign * (0.85 + TgMotion.rubberBand(absNext - 0.85));
    _move.value = damped;

    final hasAction = (damped > 0 && widget.startAction != null) ||
        (damped < 0 && widget.endAction != null);
    final crossed = hasAction && damped.abs() >= widget.threshold;
    if (crossed != _crossedThreshold) {
      _crossedThreshold = crossed;
      if (crossed) {
        unawaited(AppHaptics.play(AppHaptics.selection));
        if (!_reduceMotion) {
          _revealBounce.value = 1.18;
          unawaited(
            _revealBounce.animateWith(
              SpringSimulation(TgMotion.tactileSpring, 1.18, 1.0, 0),
            ),
          );
        }
      }
    }
  }

  Future<void> _onEnd(DragEndDetails details) async {
    final value = _move.value;
    final velocity = (details.primaryVelocity ?? 0) / _width;
    final magnitude = value.abs();
    final fast = velocity.abs() > 1.6 && magnitude > widget.threshold * 0.4;
    final shouldCommit = magnitude >= widget.threshold || fast;
    _crossedThreshold = false;

    if (!shouldCommit) {
      await _springBack(velocity: velocity);
      return;
    }
    if (value > 0) {
      // Right swipe: tactile confirm + velocity-coupled spring-back.
      unawaited(AppHaptics.play(AppHaptics.success));
      widget.onStartSwipe?.call();
      await _springBack(velocity: velocity * 0.25);
      return;
    }
    // Left swipe: animate out immediately. Caller may provide undo via
    // a SnackBar after [onDismissed] fires (commonly by un-doing the
    // underlying state mutation).
    if (widget.onDismissed == null) {
      await _springBack(velocity: velocity);
      return;
    }
    unawaited(AppHaptics.play(AppHaptics.lightImpact));
    await _dismissToEnd();
  }

  Future<void> _dismissToEnd() async {
    await _flyOff(-1);
    if (!mounted) return;
    await _collapseDown();
    if (!mounted) return;
    widget.onDismissed!.call();
  }

  Future<void> _springBack({double velocity = 0}) {
    if (_reduceMotion) {
      _move.value = 0;
      return Future<void>.value();
    }
    return _move.animateWith(
      SpringSimulation(
        TgMotion.snappySpring,
        _move.value,
        0,
        velocity.clamp(-4.0, 4.0),
      ),
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
        final eased = TgMotion.easeOutQuint.transform(t);
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
                      iconPulse: _revealBounce.value,
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
///
/// The card keeps itself alive inside a lazy list. A [ListView] disposes
/// children that scroll out of its cache extent and mounts them again on the
/// way back; without this the re-mounted card would replay the animation
/// from zero height, and a card growing above the viewport pushes everything
/// below it down — the list visibly jumps (most noticeably during the bounce
/// back from the bottom edge). An entry animation belongs to the item's first
/// appearance, not to every re-mount.
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
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _started = false;

  @override
  bool get wantKeepAlive => true;

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
    super.build(context);
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
    required this.iconPulse,
    required this.alignToEnd,
    required this.borderRadius,
  });

  final SwipeAction action;
  final double progress;
  final double iconPulse;
  final bool alignToEnd;
  final BorderRadius borderRadius;

  static const _emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);

  @override
  Widget build(BuildContext context) {
    final eased = _emphasizedDecelerate.transform(progress.clamp(0.0, 1.0));
    final opacity = (eased * 1.2).clamp(0.0, 1.0);
    final iconScale = (0.7 + eased * 0.4) * iconPulse;

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
