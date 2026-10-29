import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../utils/platform.dart';
import 'sf_symbol_glyphs.dart';

class IosNativeTabBarItem {
  const IosNativeTabBarItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.sfSymbol,
    required this.selectedSfSymbol,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String sfSymbol;
  final String selectedSfSymbol;
}

class IosNativeTabBar extends StatefulWidget {
  const IosNativeTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;

  /// Called with the tapped tab — the selected one included, which is how the
  /// shell knows to return that tab to its root.
  final ValueChanged<int> onSelected;
  final List<IosNativeTabBarItem> items;

  /// Where a portrait phone's tab bar draws its items, measured on iOS 26: the
  /// Liquid Glass capsule sits [liquidGlassHorizontalInset] in from each side
  /// and [liquidGlassTop] below the top of the view, is
  /// [liquidGlassCapsuleHeight] tall, and splits its width equally between the
  /// items. The legacy bar spans the full width with 49pt-tall items.
  static const double liquidGlassHorizontalInset = 21;
  static const double liquidGlassTop = 14;
  static const double liquidGlassCapsuleHeight = 61;
  static const double legacyItemHeight = 49;

  /// Wider than this (landscape, iPad) UITabBar centres compact items instead
  /// of splitting the width, so where an item is cannot be known from here.
  static const double maxEqualSplitWidth = 500;

  @override
  State<IosNativeTabBar> createState() => _IosNativeTabBarState();
}

class _IosNativeTabBarState extends State<IosNativeTabBar> {
  int? _downPointer;
  Offset? _downPosition;

  /// The launch screen stays up until the native bar can be drawn, at most
  /// this long. Without the hold a cold start shows CNTabBar's stand-ins
  /// first: its Flutter CupertinoTabBar while it prepares the native view
  /// (500ms of it in a debug build), then an empty band while UIKit creates
  /// that view, and only then the Liquid Glass bar — three different bars in
  /// the first second.
  static const _firstFrameHoldLimit = Duration(seconds: 2);
  static bool _firstFrameHoldTaken = false;
  bool _holdingFirstFrame = false;
  Timer? _firstFrameHoldTimer;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    if (usesIosLiquidGlass() &&
        !_firstFrameHoldTaken &&
        !binding.firstFrameRasterized) {
      _firstFrameHoldTaken = true;
      _holdingFirstFrame = true;
      binding.deferFirstFrame();
      _firstFrameHoldTimer = Timer(_firstFrameHoldLimit, _releaseFirstFrame);
      binding.addPostFrameCallback(_checkNativeBarReady);
    }
  }

  @override
  void dispose() {
    _releaseFirstFrame();
    super.dispose();
  }

  /// UiKitView lays out an empty box until UIKit has created its view, so a
  /// RenderUiKitView below the bar means the next frame shows the real bar.
  void _checkNativeBarReady(Duration _) {
    if (!_holdingFirstFrame || !mounted) return;
    var ready = false;
    void visit(Element element) {
      if (ready) return;
      if (element.renderObject is RenderUiKitView) {
        ready = true;
        return;
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    if (ready) {
      _releaseFirstFrame();
    } else {
      WidgetsBinding.instance.addPostFrameCallback(_checkNativeBarReady);
    }
  }

  void _releaseFirstFrame() {
    _firstFrameHoldTimer?.cancel();
    _firstFrameHoldTimer = null;
    if (!_holdingFirstFrame) return;
    _holdingFirstFrame = false;
    WidgetsBinding.instance.allowFirstFrame();
  }

  int get _selected => widget.selectedIndex.clamp(0, widget.items.length - 1);

  void _select(int index) {
    if (index < 0 || index >= widget.items.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onSelected(index);
  }

  /// The tab drawn under [position], or null where no item is known to be —
  /// outside the bar's visible band, or in a layout whose item frames this
  /// cannot derive. Null means "not a tap on the selected tab", which is the
  /// safe answer: a wrong guess would pop a tab the user did not tap.
  int? _indexAt(Offset position, double width) {
    if (width > IosNativeTabBar.maxEqualSplitWidth) return null;
    final glass = usesIosLiquidGlass();
    final top = glass ? IosNativeTabBar.liquidGlassTop : 0.0;
    final bottom =
        top + (glass ? IosNativeTabBar.liquidGlassCapsuleHeight : IosNativeTabBar.legacyItemHeight);
    if (position.dy < top || position.dy >= bottom) return null;
    final inset = glass ? IosNativeTabBar.liquidGlassHorizontalInset : 0.0;
    final span = width - inset * 2;
    if (span <= 0 || position.dx < inset || position.dx >= width - inset) {
      return null;
    }
    return ((position.dx - inset) / span * widget.items.length)
        .floor()
        .clamp(0, widget.items.length - 1);
  }

  // UITabBar reports a tap only when it changes the selection, so a tap on the
  // selected tab never reaches Dart through the plugin. The Listener sees the
  // same touch without entering the gesture arena, so the native bar still
  // gets it, and a tap that starts and ends on the selected tab is reported
  // here instead.
  void _onPointerDown(PointerDownEvent event) {
    if (_downPointer != null) return;
    _downPointer = event.pointer;
    _downPosition = event.localPosition;
  }

  void _onPointerUp(PointerUpEvent event, double width) {
    if (event.pointer != _downPointer) return;
    final down = _downPosition!;
    _clearPointer();
    if ((event.localPosition - down).distance > kTouchSlop) return;
    final index = _indexAt(event.localPosition, width);
    if (index != null && index == _selected && _indexAt(down, width) == index) {
      _select(index);
    }
  }

  void _clearPointer() {
    _downPointer = null;
    _downPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.length < 2) return const SizedBox.shrink();
    final nativeGlass = usesIosLiquidGlass();
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerUp: (event) => _onPointerUp(event, constraints.maxWidth),
        onPointerCancel: (_) => _clearPointer(),
        child: CNTabBar(
          // CNTabBar 1.8.1 places UITabBar 14pt below its container's top.
          // Reserve that headroom so the bar itself keeps its original height.
          height: 49 + MediaQuery.viewPaddingOf(context).bottom + (nativeGlass ? 14 : 0),
          // The native adapter treats zero as an unspecified symbol size,
          // matching UIImage(systemName:) in the previous implementation. The
          // Flutter fallback needs an explicit, nonzero icon size.
          iconSize: nativeGlass ? 0 : 25,
          currentIndex: _selected,
          tint: Theme.of(context).colorScheme.primary,
          items: [
            for (final item in widget.items)
              CNTabBarItem(
                label: item.label,
                icon: CNSymbol(item.sfSymbol),
                activeIcon: CNSymbol(item.selectedSfSymbol),
                // Before iOS 26 the bar is Flutter's CupertinoTabBar, which
                // prefers these over the symbols: Flutter glyphs, not native
                // icon views that would take the tap. See cupertinoGlyphFor.
                customIcon: nativeGlass ? null : cupertinoGlyphFor(item.sfSymbol),
                activeCustomIcon:
                    nativeGlass ? null : cupertinoGlyphFor(item.selectedSfSymbol),
              ),
          ],
          // A reselect is the Listener's to report; taking it from here too
          // would report it twice wherever the plugin does forward one.
          onTap: (index) {
            if (index != _selected) _select(index);
          },
        ),
      ),
    );
  }
}
