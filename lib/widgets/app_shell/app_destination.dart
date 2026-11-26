import 'package:flutter/material.dart';

import '../ios/ios_native_tab_bar.dart';

class AppDestination {
  final String label;
  final String? shortLabel;
  final IconData icon;
  final IconData selectedIcon;
  final String sfSymbol;
  final String selectedSfSymbol;
  final Widget page;

  const AppDestination({
    required this.label,
    this.shortLabel,
    required this.icon,
    required this.selectedIcon,
    required this.sfSymbol,
    required this.selectedSfSymbol,
    required this.page,
  });

  IosNativeTabBarItem toIosNativeTabBarItem() {
    return IosNativeTabBarItem(
      label: label,
      shortLabel: shortLabel,
      icon: icon,
      selectedIcon: selectedIcon,
      sfSymbol: sfSymbol,
      selectedSfSymbol: selectedSfSymbol,
    );
  }
}
