import 'package:flutter/cupertino.dart';

import 'ios_symbol_icons.dart';

class IosGlassTabBarItem {
  const IosGlassTabBarItem({
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

class IosGlassTabBar extends StatelessWidget {
  const IosGlassTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<IosGlassTabBarItem> items;

  int get _safeSelectedIndex {
    if (items.isEmpty) return 0;
    return selectedIndex.clamp(0, items.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return CupertinoTabBar(
      currentIndex: _safeSelectedIndex,
      onTap: onSelected,
      backgroundColor: CupertinoColors.systemBackground.withValues(alpha: 0.86),
      activeColor: CupertinoTheme.of(context).primaryColor,
      inactiveColor: CupertinoColors.inactiveGray.resolveFrom(context),
      items: [
        for (final item in items)
          BottomNavigationBarItem(
            label: item.label,
            icon: Icon(
              iosIconForSfSymbol(item.sfSymbol, fallback: item.icon),
            ),
            activeIcon: Icon(
              iosIconForSfSymbol(
                item.selectedSfSymbol,
                fallback: item.selectedIcon,
              ),
            ),
          ),
      ],
    );
  }
}
