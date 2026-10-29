import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../utils/platform.dart';

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

  /// How far the Liquid Glass capsule sits in from each side of the bar; the
  /// items share the width between those insets equally. The legacy bar spans
  /// the full width.
  static const double liquidGlassHorizontalInset = 21;

  @override
  State<IosNativeTabBar> createState() => _IosNativeTabBarState();
}

class _IosNativeTabBarState extends State<IosNativeTabBar> {
  int? _downPointer;
  Offset? _downPosition;

  int get _selected => widget.selectedIndex.clamp(0, widget.items.length - 1);

  void _select(int index) {
    if (index < 0 || index >= widget.items.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onSelected(index);
  }

  /// The tab under [x], measured across this bar's width.
  int? _indexAt(double x, double width) {
    final inset =
        usesIosLiquidGlass() ? IosNativeTabBar.liquidGlassHorizontalInset : 0.0;
    final span = width - inset * 2;
    if (span <= 0 || x < inset || x > width - inset) return null;
    return ((x - inset) / span * widget.items.length)
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
    final index = _indexAt(event.localPosition.dx, width);
    if (index != null &&
        index == _selected &&
        _indexAt(down.dx, width) == index) {
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
          height: 49 +
              MediaQuery.viewPaddingOf(context).bottom +
              (nativeGlass ? 14 : 0),
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
