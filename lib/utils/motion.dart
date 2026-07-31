import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';

/// Motion constants distilled from the Telegram Android source
/// (see ~/repos/Telegram/UI-STUDY for the full study).
///
/// Telegram's signature feel comes from a *small* shared dictionary of
/// curves and durations reused everywhere, not from per-widget tuning.
abstract final class TgMotion {
  /// Telegram's `CubicBezierInterpolator.DEFAULT` — CSS `ease`.
  static const Curve ease = Cubic(0.25, 0.1, 0.25, 1);

  /// Telegram's brand curve `EASE_OUT_QUINT` (.23, 1, .32, 1): ~80% of the
  /// distance in the first ~20% of the time, long soft tail. Flutter's
  /// built-in constant has identical control points.
  static const Curve easeOutQuint = Curves.easeOutQuint;

  /// The "mother curve" shared by keyboard rise, chat-list shifts and the
  /// send-message transition (`ChatListItemAnimator.DEFAULT_INTERPOLATOR`).
  /// Sharing one curve + duration across concurrently moving surfaces makes
  /// them read as a single rigid body.
  static const Curve keyboard = Cubic(0.1992, 0.0106, 0.2792, 0.9103);
  static const Duration keyboardDuration = Duration(milliseconds: 250);

  /// Tap-to-switch page scroll (`ViewPagerFixed.getManualScrollDuration`).
  static const Duration pageSwitch = Duration(milliseconds: 540);

  /// Main-tabs pager override (`ViewPagerActivity` inner pager): page slides
  /// between bottom-bar tabs settle in 320ms — the same length as the tab
  /// selector pop, so bar and page share one timeline. Curve: [easeOutQuint].
  static const Duration tabsPageSwitch = Duration(milliseconds: 320);

  /// Common duration grid; prefer these over ad-hoc values.
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration short = Duration(milliseconds: 200);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration long = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 420);
}

/// Port of Telegram's `AnimatedFloat` (`ui/Components/AnimatedFloat.java`):
/// a lazy tracker that turns abrupt target changes into smooth transitions.
///
/// Call [set] with the *current desired value* on every build/paint. When the
/// target changes, the value glides there from wherever it is displayed right
/// now — mid-flight retargets never jump. While a transition is running the
/// [_invalidate] callback is fired so the owner schedules another frame.
///
/// The very first [set] snaps without animating, so freshly created widgets
/// render their true state immediately instead of fading in from zero.
class AnimatedFloat {
  AnimatedFloat(
    this._invalidate, {
    this.duration = const Duration(milliseconds: 200),
    this.curve = TgMotion.ease,
  });

  /// Shared monotonic clock, mirroring Telegram's `elapsedRealtime()`.
  static final Stopwatch _clock = Stopwatch()..start();

  /// Asks the owner to schedule one more frame (e.g. a coalesced setState).
  final void Function() _invalidate;
  final Duration duration;
  final Curve curve;

  double _value = 0;
  double _target = 0;
  double _startValue = 0;
  int _startMs = 0;
  bool _firstSet = true;

  bool get isInProgress => _value != _target;

  /// Declare what the value should be right now; returns what to display
  /// this frame. Pass `force: true` to snap (e.g. when a cell is rebound).
  double set(double target, {bool force = false}) {
    if (force || _firstSet || duration <= Duration.zero) {
      _firstSet = false;
      _value = _target = target;
      return _value;
    }
    if ((target - _target).abs() > 0.0001) {
      _startValue = _value;
      _target = target;
      _startMs = _clock.elapsedMilliseconds;
    }
    return _advance();
  }

  /// Boolean convenience: `set(active)` in Telegram code.
  double setBool(bool target, {bool force = false}) =>
      set(target ? 1 : 0, force: force);

  /// Current value, advanced against the clock (also requests a frame while
  /// unsettled). Prefer [set]; use this only where the target cannot change.
  double get value => _advance();

  double _advance() {
    if (_value != _target) {
      final ms = duration.inMilliseconds;
      final t = ((_clock.elapsedMilliseconds - _startMs) / ms).clamp(0.0, 1.0);
      _value = t >= 1
          ? _target
          : lerpDouble(_startValue, _target, curve.transform(t))!;
      if (_value != _target) _invalidate();
    }
    return _value;
  }
}
