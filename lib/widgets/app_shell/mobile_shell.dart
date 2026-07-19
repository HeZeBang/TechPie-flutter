import 'package:flutter/material.dart';

import '../../utils/platform.dart';
import '../ios_liquid/ios_glass_button.dart';
import '../ios_liquid/ios_glass_tab_bar.dart';
import 'app_destination.dart';

class MobileShell extends StatelessWidget {
  final List<AppDestination> destinations;
  final int selectedIndex;
  final int assignmentsIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  const MobileShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.assignmentsIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final usesIosChrome = isIos();

    return Scaffold(
      extendBody: true,
      body: child,
      floatingActionButton: selectedIndex == assignmentsIndex
          ? usesIosChrome
              ? IosGlassButton(
                  onPressed: () {},
                  icon: Icons.add,
                  sfSymbol: 'plus',
                )
              : FloatingActionButton(
                  onPressed: () {},
                  child: const Icon(Icons.add),
                )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: usesIosChrome
          ? IosGlassTabBar(
              selectedIndex: selectedIndex,
              items: destinations
                  .map((item) => item.toIosGlassTabBarItem())
                  .toList(),
              onSelected: onDestinationSelected,
            )
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              // The selection indicator is the persistent selected state.
              // Suppress transient state layers so they do not overlap it.
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              destinations: [
                for (var index = 0; index < destinations.length; index++)
                  NavigationDestination(
                    icon: _NavigationDestinationIcon(
                      icon: destinations[index].icon,
                      selectedIcon: destinations[index].selectedIcon,
                      selected: index == selectedIndex,
                    ),
                    label: destinations[index].label,
                  ),
              ],
            ),
    );
  }
}

class _NavigationDestinationIcon extends StatelessWidget {
  const _NavigationDestinationIcon({
    required this.icon,
    required this.selectedIcon,
    required this.selected,
  });

  final IconData icon;
  final IconData selectedIcon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final displayedIcon = selected ? selectedIcon : icon;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Icon(displayedIcon, key: ValueKey(displayedIcon)),
    );
  }
}
