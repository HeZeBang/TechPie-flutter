import 'package:flutter/material.dart';

import '../ios/ios_native_tab_bar.dart';

class AppDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String sfSymbol;
  final String selectedSfSymbol;
  final Widget page;

  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.sfSymbol,
    required this.selectedSfSymbol,
    required this.page,
  });

  IosNativeTabBarItem toIosNativeTabBarItem() {
    return IosNativeTabBarItem(
      label: label,
      icon: icon,
      selectedIcon: selectedIcon,
      sfSymbol: sfSymbol,
      selectedSfSymbol: selectedSfSymbol,
    );
  }
}
