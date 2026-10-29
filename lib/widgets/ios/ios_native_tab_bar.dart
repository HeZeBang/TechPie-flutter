import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

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
    return CNTabBar(
      height: 49 + MediaQuery.viewPaddingOf(context).bottom,
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
