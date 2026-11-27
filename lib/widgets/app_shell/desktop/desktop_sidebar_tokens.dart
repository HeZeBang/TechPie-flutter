import 'package:flutter/material.dart';

/// Live badge metadata shown on a desktop sidebar destination (e.g. pending
/// Deadlines count + whether any item is due within 24h or in late window).
@immutable
class SidebarBadgeData {
  const SidebarBadgeData({
    required this.count,
    this.urgent = false,
  });

  final int count;
  final bool urgent;

  String get formatted => count > 99 ? '99+' : '$count';
}

/// Compact account status summary shown in the desktop sidebar footer.
@immutable
class DesktopSidebarAccountSummary {
  const DesktopSidebarAccountSummary({
    required this.displayName,
    required this.avatarText,
    required this.isLoggedIn,
    this.boundPlatformCount = 0,
  });

  final String displayName;
  final String avatarText;
  final bool isLoggedIn;
  final int boundPlatformCount;
}

abstract final class DesktopSidebarTokens {
  static const double collapsedWidth = 78;
  static const double mediumExpandedWidth = 120;
  static const double expandedWidthFactor = 0.2;
  static const double maxExpandedWidth = 228;

  static const Duration widthAnimationDuration = Duration(milliseconds: 180);
  static const Curve widthAnimationCurve = Curves.easeOutCubic;

  static const double macOsTitlebarRowHeight = 38;
  static const double headerHeight = 56;
  static const double collapsedHorizontalPadding = 17;
  static const double mediumHorizontalPadding = 12;
  static const double expandedHorizontalPadding = 12;
  static const double headerTopPadding = 10;
  static const double headerBottomPadding = 8;

  static const double brandHeight = 36;
  static const double brandIconSize = 22;
  static const double brandTextGap = navItemTextGap;

  static const double toggleButtonSize = 32;
  static const double toggleIconSize = 18;
  static const double iconColumnWidth = 44;

  static const double navTopPadding = 4;
  static const double navBottomPadding = 12;
  static const double navItemSpacing = 3;
  static const double navItemHeight = 40;
  static const double mediumNavItemSpacing = 8;
  static const double mediumNavItemHeight = 76;
  static const double navItemRadius = 8;
  static const double navItemIconSize = 22;
  static const double navItemTextGap = 10;
  static const double minLabelWidth = 52;
}
