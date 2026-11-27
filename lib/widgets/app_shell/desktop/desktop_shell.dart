import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/tp_colors.dart';
import '../app_destination.dart';
import 'desktop_sidebar.dart';
import 'desktop_sidebar_tokens.dart';

class DesktopShell extends StatelessWidget {
  final List<AppDestination> destinations;
  final int selectedIndex;
  final bool sidebarCollapsed;
  final bool showToggleButton;
  final Map<int, SidebarBadgeData> badges;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onToggleSidebarCollapsed;
  final VoidCallback? onOpenCommandPalette;
  final VoidCallback? onBrandTap;
  final DesktopSidebarAccountSummary? accountSummary;
  final int? accountDestinationIndex;
  final VoidCallback? onOpenAccount;
  final Widget child;

  const DesktopShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.sidebarCollapsed,
    this.showToggleButton = true,
    this.badges = const <int, SidebarBadgeData>{},
    required this.onDestinationSelected,
    required this.onToggleSidebarCollapsed,
    this.onOpenCommandPalette,
    this.onBrandTap,
    this.accountSummary,
    this.accountDestinationIndex,
    this.onOpenAccount,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sidebarWidth = sidebarCollapsed
              ? DesktopSidebarTokens.collapsedWidth
              : math.min(
                  constraints.maxWidth *
                      DesktopSidebarTokens.expandedWidthFactor,
                  DesktopSidebarTokens.maxExpandedWidth,
                );
          return Row(
            children: [
              AnimatedContainer(
                duration: DesktopSidebarTokens.widthAnimationDuration,
                curve: DesktopSidebarTokens.widthAnimationCurve,
                width: sidebarWidth,
                child: DesktopSidebar(
                  destinations: destinations,
                  selectedIndex: selectedIndex,
                  collapsed: sidebarCollapsed,
                  showToggleButton: showToggleButton,
                  badges: badges,
                  onSelected: onDestinationSelected,
                  onToggleCollapsed: onToggleSidebarCollapsed,
                  onOpenCommandPalette: onOpenCommandPalette,
                  onBrandTap: onBrandTap,
                  accountSummary: accountSummary,
                  accountDestinationIndex: accountDestinationIndex,
                  onOpenAccount: onOpenAccount,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 0.5,
                color: colors.divider,
              ),
              Expanded(child: SizedBox.expand(child: child)),
            ],
          );
        },
      ),
    );
  }
}
