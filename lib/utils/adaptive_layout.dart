import 'package:flutter/widgets.dart';

import 'platform.dart';

enum AppWindowSizeClass { compact, medium, expanded }

const double mediumWindowBreakpoint = 600;
const double expandedWindowBreakpoint = 960;

AppWindowSizeClass appWindowSizeClassFor(double width) {
  if (width >= expandedWindowBreakpoint) {
    return AppWindowSizeClass.expanded;
  }
  if (width >= mediumWindowBreakpoint) {
    return AppWindowSizeClass.medium;
  }
  return AppWindowSizeClass.compact;
}

AppWindowSizeClass appWindowSizeClassOf(BuildContext context) {
  return appWindowSizeClassFor(MediaQuery.sizeOf(context).width);
}

bool usesSidebarLayout(BuildContext context) {
  return appWindowSizeClassOf(context) != AppWindowSizeClass.compact;
}

/// Whether [AppShell] displays the desktop sidebar instead of the bottom bar.
///
/// Native desktop windows enter the sidebar shell at `>= 600dp` (auto-collapsing
/// to a compact icon rail across `600–959dp`), whereas mobile targets reserve
/// the sidebar shell for wide (`>= 960dp`) tablet/foldable layouts.
bool usesDesktopSidebarShell(BuildContext context) {
  final sizeClass = appWindowSizeClassOf(context);
  if (sizeClass == AppWindowSizeClass.expanded) return true;
  return isDesktop() && sizeClass == AppWindowSizeClass.medium;
}

/// Whether a desktop window is in the `600–959dp` medium tier and should keep
/// its sidebar automatically collapsed as an icon rail.
bool usesAutoCollapsedSidebarRail(BuildContext context) {
  return isDesktop() &&
      appWindowSizeClassOf(context) == AppWindowSizeClass.medium;
}
