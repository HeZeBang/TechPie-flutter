import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

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

class _TgBottomNavBarState extends State<TgBottomNavBar> {
  // GlassTabView's isSelectedAnimator: BoolAnimator(320ms, DECELERATE).
  late final List<AnimatedFloat> _selectedT = [
    for (final _ in widget.destinations)
      AnimatedFloat(
        _invalidate,
        duration: TgMotion.medium,
        curve: Curves.decelerate,
      ),
  ];

  bool _framePending = false;

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const capsule = BorderRadius.all(
      Radius.circular(TgBottomNavBar.barHeight / 2),
    );

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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: capsule,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: capsule,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      height: TgBottomNavBar.barHeight,
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.72),
                        borderRadius: capsule,
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                          width: 0.5,
                        ),
                      ),
                      // MainTabsLayout padding = MARGIN + 4 = 12, of which 8 is
                      // the glass inset — tab cells sit 4dp inside the capsule.
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          for (var i = 0; i < widget.destinations.length; i++)
                            Expanded(child: _buildTab(i, scheme)),
                        ],
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
    final t = _selectedT[index].setBool(index == widget.selectedIndex);
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
            selectedT: t,
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
              // Label at 28.33dp, bold; the original swaps to an extra-bold
              // typeface when selected — crossfade the two weights.
              Positioned(
                top: 28.33,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: 1 - t,
                      child: _label(destination.label, FontWeight.w700, tint),
                    ),
                    Opacity(
                      opacity: t,
                      child: _label(destination.label, FontWeight.w800, tint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text, FontWeight weight, Color tint) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, fontWeight: weight, color: tint),
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
