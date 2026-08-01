import 'package:flutter/widgets.dart';

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
