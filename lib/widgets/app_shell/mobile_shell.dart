import 'package:flutter/material.dart';

import '../../utils/platform.dart';
import '../ios/ios_native_tab_bar.dart';
import 'app_destination.dart';
import 'app_shell_metrics.dart';
import 'app_shell_tab_bar.dart';
import 'tg_bottom_nav_bar.dart';

class MobileShell extends StatefulWidget {
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
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  final _tabBar = AppShellTabBarController();

  @override
  void dispose() {
    _tabBar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShellTabBar(
      controller: _tabBar,
      child: ListenableBuilder(
        listenable: _tabBar,
        builder: (context, _) => _buildShell(context, tabBarHidden: _tabBar.hidden),
      ),
    );
  }

  Widget _buildShell(BuildContext context, {required bool tabBarHidden}) {
    final usesIosChrome = isIos();
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    // While a page stands in for the bar it covers nothing, so the page's own
    // toolbar sits on the home indicator's safe area, where the bar was.
    final bottomObstruction = tabBarHidden
        ? bottomInset
        : (usesIosChrome ? 49.0 : TgBottomNavBar.barHeight + TgBottomNavBar.margin * 2) +
            bottomInset;

    return AppShellMetrics(
      bottomObstruction: bottomObstruction,
      child: Scaffold(
        extendBody: true,
        // The bar is part of the safe area, as it is for a UITabBarController's
        // children: every page in a tab — pushed ones too — reads it from
        // MediaQuery, so SafeArea and default list padding keep the last row
        // clear of it. Scaffold would report the bar's whole view, including
        // the transparent headroom above the glass capsule; this is the part
        // it actually covers.
        body: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(bottom: bottomObstruction),
              ),
              child: widget.child,
            );
          },
        ),
        // Collapsed rather than removed while hidden, so the native tab bar is
        // not recreated — and does not flash — when it comes back.
        bottomNavigationBar: ClipRect(
          clipBehavior: tabBarHidden ? Clip.hardEdge : Clip.none,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: tabBarHidden ? 0 : 1,
            child: IgnorePointer(
              ignoring: tabBarHidden,
              child: ExcludeSemantics(
                excluding: tabBarHidden,
                child: usesIosChrome
                    ? IosNativeTabBar(
                        selectedIndex: widget.selectedIndex,
                        items: widget.destinations
                            .map((item) => item.toIosNativeTabBarItem())
                            .toList(),
                        onSelected: widget.onDestinationSelected,
                      )
                    : TgBottomNavBar(
                        destinations: widget.destinations,
                        selectedIndex: widget.selectedIndex,
                        onDestinationSelected: widget.onDestinationSelected,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
