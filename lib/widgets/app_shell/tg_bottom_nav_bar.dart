import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../utils/glass.dart';
import '../../utils/motion.dart';
import 'app_destination.dart';

/// Telegram-style bottom navigation bar, ported from the official client's
/// main tabs (`ui/Components/glass/GlassTabView.java` + `ui/MainTabsLayout.java`
/// + `ui/MainTabsActivity.java`; study in ~/repos/Telegram/UI-STUDY).
///
/// A floating frosted-glass capsule (56dp tall, radius = height/2, 8dp
/// margins — `MAIN_TABS_HEIGHT` / `MAIN_TABS_MARGIN`). Selection has no
/// sliding indicator and no ink ripple: each tab owns a soft capsule of the
/// accent color at 9% alpha that scales in from 0.6 (320ms decelerate) while
/// icon and label tint toward the accent and the label gains weight. The
/// capsule pop itself is the touch feedback, exactly like the original.
///
/// Long-pressing the bar detaches the capsule: it spring-glides to the
/// finger, follows it across tabs (selection tracks continuously), the whole
/// bar swells to 1.019× tilted toward the touch point, and on release the
/// capsule spring-snaps onto the final tab before per-tab drawing resumes.
class TgBottomNavBar extends StatefulWidget {
  const TgBottomNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<AppDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// `DialogsActivity.MAIN_TABS_HEIGHT`.
  static const double barHeight = 56;

  /// `DialogsActivity.MAIN_TABS_MARGIN` — gap to screen edges and bottom.
  static const double margin = 8;

  /// `MainTabsLayout.setMaxWidth(328 + MARGIN * 2)` — on wide screens the
  /// capsule stays compact and centered instead of stretching.
  static const double maxWidth = 344;

  @override
  State<TgBottomNavBar> createState() => _TgBottomNavBarState();
}

class _TgBottomNavBarState extends State<TgBottomNavBar> with TickerProviderStateMixin {
  // GlassTabView's isSelectedAnimator: BoolAnimator(320ms, DECELERATE).
  late final List<AnimatedFloat> _selectedT = [
    for (final _ in widget.destinations)
      AnimatedFloat(
        _invalidate,
        duration: TgMotion.medium,
        curve: Curves.decelerate,
      ),
  ];

  // MainTabsLayout.animatorIsScaled: 1 → 1.019 while long-pressing.
  late final AnimatedFloat _barScaleT = AnimatedFloat(
    _invalidate,
    duration: const Duration(milliseconds: 380),
    curve: TgMotion.easeOutQuint,
  );

  // MainTabsLayout's drag springs: STIFFNESS_MEDIUM + DAMPING_RATIO_LOW_BOUNCY.
  static final SpringDescription _dragSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1500, ratio: 0.75);

  /// Initial glide of the capsule from the selected tab to the finger.
  late final AnimationController _glideX;

  /// Release snap of the capsule onto the final tab center.
  late final AnimationController _settleX;

  @override
  void initState() {
    super.initState();
    _glideX = AnimationController.unbounded(vsync: this)
      ..addListener(_onSpringTick);
    _settleX = AnimationController.unbounded(vsync: this)
      ..addListener(_onSpringTick);
  }

  bool _dragging = false;
  bool _settling = false;
  int? _dragIndex;
  double _dragX = 0;
  Offset _scalePivot = Offset.zero;
  int _restoreToken = 0;
  double _contentWidth = 0;
  double _contentHeight = 0;

  bool _framePending = false;

  void _onSpringTick() => setState(() {});

  /// Coalesced "one more frame please" used by the AnimatedFloats: rebuild on
  /// the next frame, not synchronously (set() runs during build).
  void _invalidate() {
    if (_framePending) return;
    _framePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _framePending = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  double get _cellWidth => _contentWidth / widget.destinations.length;

  double _centerOf(int index) => _cellWidth * (index + 0.5);

  int _nearestIndex(double x) => (x / _cellWidth).floor().clamp(0, widget.destinations.length - 1);

  double get _freeCapsuleX => _settling ? _settleX.value : _dragX + _glideX.value;

  bool get _capsuleDetached => _dragging || _settling;

  void _onLongPressStart(LongPressStartDetails details) {
    if (_contentWidth <= 0) return;
    _restoreToken++;
    unawaited(HapticFeedback.mediumImpact());
    _settleX.stop();
    _dragging = true;
    _settling = false;
    _dragX = _clampToCenters(details.localPosition.dx);
    // The capsule starts where the selected tab's own capsule was and
    // spring-glides to the finger — a seamless detach, never a jump.
    final glideFrom = _centerOf(widget.selectedIndex) - _dragX;
    _glideX.value = glideFrom;
    unawaited(_glideX.animateWith(SpringSimulation(_dragSpring, glideFrom, 0, 0)));
    final nearest = _nearestIndex(details.localPosition.dx);
    _dragIndex = nearest;
    // Like the original's checkLongMove(start): a long-press away from the
    // selected tab commits that tab (and its page) immediately.
    if (nearest != widget.selectedIndex) {
      widget.onDestinationSelected(nearest);
    }
    _updatePivot(details.localPosition);
    setState(() {});
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_dragging) return;
    _dragX = _clampToCenters(details.localPosition.dx);
    // Mid-drag only the visuals track the finger; the page commits on release.
    _dragIndex = _nearestIndex(details.localPosition.dx);
    _updatePivot(details.localPosition);
    setState(() {});
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_dragging) return;
    final target = _dragIndex ?? widget.selectedIndex;
    if (target != widget.selectedIndex) {
      widget.onDestinationSelected(target);
    }
    _dragging = false;
    _settling = true;
    _glideX.stop();
    final from = _dragX + _glideX.value;
    _settleX.value = from;
    unawaited(
      _settleX.animateWith(
        SpringSimulation(
          _dragSpring,
          from,
          _centerOf(target),
          details.velocity.pixelsPerSecond.dx,
        ),
      ),
    );
    // The original hands drawing back to the tabs 450ms after release, once
    // the spring has landed where the per-tab capsule already is.
    final token = ++_restoreToken;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (mounted && token == _restoreToken) {
          setState(() {
            _settling = false;
            _dragIndex = null;
          });
        }
      }),
    );
    setState(() {});
  }

  double _clampToCenters(double x) => x.clamp(
        _centerOf(0),
        _centerOf(widget.destinations.length - 1),
      );

  /// `MainTabsLayout.checkPivot`: the bar's scale pivot is the touch point
  /// pushed outward non-linearly (mapped r = 1.5r/(r+0.5)) with the vertical
  /// component exaggerated ×3 — the bar "bends" toward the finger.
  void _updatePivot(Offset local) {
    final w = _contentWidth;
    final h = _contentHeight;
    if (w <= 0 || h <= 0) return;
    final cx = w / 2;
    final cy = h / 2;
    final dx = local.dx - cx;
    final dy = local.dy - cy;
    final nx = dx / (w / 2);
    final ny = dy / (h / 2);
    final r = math.sqrt(nx * nx + ny * ny);
    double px = cx;
    double py = cy;
    if (r > 1e-4) {
      final mapped = 1.5 * r / (r + 0.5);
      final scale = mapped / r;
      px = cx + dx * scale;
      py = cy + dy * scale;
    }
    // +4 converts content coordinates to capsule coordinates (cell inset).
    _scalePivot = Offset(px + 4, cy + 3 * (py - cy) + 4);
  }

  @override
  void didUpdateWidget(covariant TgBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An outside selection change (e.g. a tap while the release spring is
    // still settling) invalidates the drag override.
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        _capsuleDetached &&
        widget.selectedIndex != _dragIndex) {
      _restoreToken++;
      _dragging = false;
      _settling = false;
      _dragIndex = null;
    }
  }

  @override
  void dispose() {
    _glideX.dispose();
    _settleX.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const capsule = BorderRadius.all(
      Radius.circular(TgBottomNavBar.barHeight / 2),
    );

    // Glass fill via inverse src-over: declare the final glass color
    // (official: light #FFFFFF / dark #232324 — mapped to the closest
    // surface-container tones so dynamic color keeps working), derive the
    // translucent overlay against what's actually behind the bar.
    final glassTarget =
        brightness == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainer;
    final glassFill = TgGlass.solveSrcColor(scheme.surface, glassTarget);

    final barScale = 1 + 0.019 * _barScaleT.setBool(_dragging);

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TgBottomNavBar.margin,
          0,
          TgBottomNavBar.margin,
          bottomInset + TgBottomNavBar.margin,
        ),
        child: SizedBox(
          height: TgBottomNavBar.barHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: TgBottomNavBar.maxWidth,
              ),
              child: Transform.scale(
                scale: barScale,
                origin: _scalePivot,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: capsule,
                    boxShadow: [
                      BoxShadow(
                        color: TgGlass.shadowColor(brightness),
                        blurRadius: TgGlass.shadowBlur,
                        offset: const Offset(0, TgGlass.shadowDy),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: capsule,
                    child: BackdropFilter(
                      filter: TgGlass.backdrop(),
                      child: CustomPaint(
                        foregroundPainter: _GlassStrokePainter(
                          top: TgGlass.strokeTop(brightness),
                          bottom: TgGlass.strokeBottom(brightness),
                          radius: TgBottomNavBar.barHeight / 2,
                        ),
                        child: Container(
                          height: TgBottomNavBar.barHeight,
                          decoration: BoxDecoration(
                            color: glassFill,
                            borderRadius: capsule,
                          ),
                          // MainTabsLayout padding = MARGIN + 4 = 12, of which
                          // 8 is the glass inset — cells sit 4dp inside.
                          padding: const EdgeInsets.all(4),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              _contentWidth = constraints.maxWidth;
                              _contentHeight = constraints.maxHeight;
                              return RawGestureDetector(
                                gestures: {
                                  LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                                      LongPressGestureRecognizer>(
                                    // ClickHelper long-press = system × 0.75.
                                    () => LongPressGestureRecognizer(
                                      duration: const Duration(milliseconds: 375),
                                      debugOwner: this,
                                    ),
                                    (recognizer) => recognizer
                                      ..onLongPressStart = _onLongPressStart
                                      ..onLongPressMoveUpdate = _onLongPressMove
                                      ..onLongPressEnd = _onLongPressEnd,
                                  ),
                                },
                                child: CustomPaint(
                                  painter: _FreeCapsulePainter(
                                    visible: _capsuleDetached,
                                    centerX: _capsuleDetached ? _freeCapsuleX : 0,
                                    cellWidth: _cellWidth,
                                    color: scheme.primary,
                                  ),
                                  child: Row(
                                    children: [
                                      for (var i = 0; i < widget.destinations.length; i++)
                                        Expanded(child: _buildTab(i, scheme)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index, ColorScheme scheme) {
    final destination = widget.destinations[index];
    final effectiveSelected =
        _capsuleDetached && _dragIndex != null ? _dragIndex! : widget.selectedIndex;
    final t = _selectedT[index].setBool(index == effectiveSelected);
    // glass_tabUnselected is a near-full-contrast neutral, glass_tabSelected
    // the accent; icon and label blend toward it as the tab activates.
    final tint = Color.lerp(scheme.onSurface, scheme.primary, t)!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onDestinationSelected(index),
      child: Semantics(
        selected: index == widget.selectedIndex,
        button: true,
        child: CustomPaint(
          painter: _TabSelectorPainter(
            // While the capsule is detached the bar paints it; tabs skip.
            selectedT: _capsuleDetached ? 0 : t,
            color: scheme.primary,
          ),
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: 4,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outline→filled crossfade stands in for the original's
                    // Lottie morph between icon variants.
                    Opacity(
                      opacity: 1 - t,
                      child: Icon(destination.icon, size: 24, color: tint),
                    ),
                    Opacity(
                      opacity: t,
                      child: Icon(
                        destination.selectedIcon,
                        size: 24,
                        color: tint,
                      ),
                    ),
                  ],
                ),
              ),
              // Label: 12dp Roboto Medium — Telegram's "bold()" is actually
              // rmedium.ttf (w500), bundled here as RobotoMedium. The
              // original's TextView sits at top 28.33 with Android font
              // padding, putting the baseline at ~41dp; Flutter has no font
              // padding, so top 30 reproduces the same baseline and the
              // ~4dp visual gap below the icon.
              Positioned(
                top: 30,
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    inherit: false,
                    fontFamily: 'RobotoMedium',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: tint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// The per-tab selection capsule (`GlassTabView.dispatchDraw`): full cell
/// bounds rounded to a stadium, accent color at 9% alpha (further eased with
/// decelerate), scaling in from 0.6 around the cell center.
class _TabSelectorPainter extends CustomPainter {
  const _TabSelectorPainter({required this.selectedT, required this.color});

  final double selectedT;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (selectedT <= 0) return;
    final alpha = Curves.decelerate.transform(selectedT);
    final scale = 0.6 + 0.4 * selectedT;
    final rect = Offset.zero & size;
    final radius = math.min(size.width, size.height) / 2;

    canvas
      ..save()
      ..translate(rect.center.dx, rect.center.dy)
      ..scale(scale)
      ..translate(-rect.center.dx, -rect.center.dy)
      ..drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = color.withValues(alpha: 0.09 * alpha),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _TabSelectorPainter old) =>
      old.selectedT != selectedT || old.color != color;
}

/// The detached long-press capsule (`MainTabsLayout.dispatchDraw` while
/// `drawCustomSelector`): a free-floating stadium at the finger-driven
/// center, painted by the bar underneath all tabs.
class _FreeCapsulePainter extends CustomPainter {
  const _FreeCapsulePainter({
    required this.visible,
    required this.centerX,
    required this.cellWidth,
    required this.color,
  });

  final bool visible;
  final double centerX;
  final double cellWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible || cellWidth <= 0) return;
    final rect = Rect.fromCenter(
      center: Offset(centerX, size.height / 2),
      width: cellWidth,
      height: size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
      Paint()..color = color.withValues(alpha: 0.09),
    );
  }

  @override
  bool shouldRepaint(covariant _FreeCapsulePainter old) =>
      old.visible != visible ||
      old.centerX != centerX ||
      old.cellWidth != cellWidth ||
      old.color != color;
}

/// The 0.4dp glass bevel: one stroked capsule whose color runs from the top
/// hairline to the bottom hairline (`strokePathTop`/`strokePathBottom` in
/// `BlurredBackgroundDrawable`, collapsed into a vertical gradient stroke).
class _GlassStrokePainter extends CustomPainter {
  const _GlassStrokePainter({
    required this.top,
    required this.bottom,
    required this.radius,
  });

  final Color top;
  final Color bottom;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(TgGlass.strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TgGlass.strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassStrokePainter old) =>
      old.top != top || old.bottom != bottom || old.radius != radius;
}
