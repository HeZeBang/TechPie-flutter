import 'package:cupertino_native_better/cupertino_native_better.dart';
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

class IosNativeTabBar extends StatelessWidget {
  const IosNativeTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<IosNativeTabBarItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.length < 2) return const SizedBox.shrink();
    final nativeGlass = usesIosLiquidGlass();
    return CNTabBar(
      // CNTabBar 1.8.1 places UITabBar 14pt below its container's top.
      // Reserve that headroom so the bar itself keeps its original height.
      height: 49 + MediaQuery.viewPaddingOf(context).bottom + (nativeGlass ? 14 : 0),
      // The native adapter treats zero as an unspecified symbol size, matching
      // UIImage(systemName:) in the previous implementation. The Flutter
      // fallback needs an explicit, nonzero icon size.
      iconSize: nativeGlass ? 0 : 25,
      currentIndex: selectedIndex.clamp(0, items.length - 1),
      tint: Theme.of(context).colorScheme.primary,
      items: [
        for (final item in items)
          CNTabBarItem(
            label: item.label,
            icon: CNSymbol(item.sfSymbol),
            activeIcon: CNSymbol(item.selectedSfSymbol),
          ),
      ],
      onTap: (index) {
        if (index >= 0 && index < items.length) {
          FocusManager.instance.primaryFocus?.unfocus();
          onSelected(index);
        }
      },
    );
  }
}
