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
  static const double collapsedWidth = 88;
  static const double mediumExpandedWidth = 120;
  static const double expandedWidthFactor = 0.2;
  static const double maxExpandedWidth = 240;

  static const Duration widthAnimationDuration = Duration(milliseconds: 180);
  static const Curve widthAnimationCurve = Curves.easeOutCubic;

  static const double headerHeight = 80;
  static const double collapsedHorizontalPadding = 20;
  static const double mediumHorizontalPadding = 12;
  static const double expandedHorizontalPadding = 20;
  static const double headerTopPadding = 16;
  static const double headerBottomPadding = 16;

  static const double brandHeight = 48;
  static const double brandIconSize = 22;
  static const double brandTextGap = 12;

  static const double toggleButtonSize = 40;
  static const double toggleIconSize = 22;
  static const double iconColumnWidth = 48;

  static const double navTopPadding = 8;
  static const double navBottomPadding = 16;
  static const double navItemSpacing = 4;
  static const double navItemHeight = 48;
  static const double mediumNavItemSpacing = 8;
  static const double mediumNavItemHeight = 76;
  static const double navItemRadius = 8;
  static const double navItemIconSize = 22;
  static const double navItemTextGap = 12;
  static const double minLabelWidth = 56;
}
