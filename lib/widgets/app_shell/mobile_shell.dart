import 'package:flutter/material.dart';

import '../../utils/platform.dart';
import '../ios/ios_native_tab_bar.dart';
import 'app_destination.dart';
import 'app_shell_metrics.dart';
import 'tg_bottom_nav_bar.dart';

class MobileShell extends StatelessWidget {
  final List<AppDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  const MobileShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final usesIosChrome = isIos();
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final bottomObstruction = (usesIosChrome
            ? 49.0
            : TgBottomNavBar.barHeight + TgBottomNavBar.margin * 2) +
        bottomInset;

    return AppShellMetrics(
      bottomObstruction: bottomObstruction,
      child: Scaffold(
        extendBody: true,
        body: child,
        bottomNavigationBar: usesIosChrome
            ? IosNativeTabBar(
                selectedIndex: selectedIndex,
                items: destinations
                    .map((item) => item.toIosNativeTabBarItem())
                    .toList(),
                onSelected: onDestinationSelected,
              )
            : TgBottomNavBar(
                destinations: destinations,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
              ),
      ),
    );
  }
}
