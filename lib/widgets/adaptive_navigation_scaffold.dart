import 'package:flutter/material.dart';

import '../utils/platform.dart';
import 'ios/ios_native_navigation_bar.dart';

/// Coordinates iOS large titles with the page's primary vertical scroll view.
/// Lists and the timetable keep their existing bodies and refresh controls.
class AdaptiveNavigationScaffold extends StatefulWidget {
  const AdaptiveNavigationScaffold({
    super.key,
    required this.appBar,
    required this.body,
    this.extendBodyBehindAppBar = false,
  });

  final PreferredSizeWidget appBar;
  final Widget body;
  final bool extendBodyBehindAppBar;

  @override
  State<AdaptiveNavigationScaffold> createState() => _AdaptiveNavigationScaffoldState();
}

class _AdaptiveNavigationScaffoldState extends State<AdaptiveNavigationScaffold> {
  final _scrollKey = GlobalKey<NestedScrollViewState>();
  double _largeTitleOffset = 0;

  @override
  void didUpdateWidget(AdaptiveNavigationScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.appBar;
    final after = widget.appBar;
    if (before is! IosNativeNavigationBar ||
        after is! IosNativeNavigationBar ||
        before.largeTitleMode == after.largeTitleMode) {
      return;
    }
    final scroll = _scrollKey.currentState;
    if (scroll == null) return;
    if (before.largeTitleMode) {
      _largeTitleOffset = scroll.outerController.offset;
    } else {
      // A compact header has a different scroll extent. After layout, restore
      // the coordinated position so exiting selection does not reopen a title
      // above a list that is still scrolled down.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = _scrollKey.currentState;
        if (state == null || !state.innerController.hasClients) return;
        final inner = state.innerController.positions.first;
        if (inner.pixels > inner.minScrollExtent) {
          state.innerController.jumpTo(inner.pixels);
        } else {
          state.outerController.jumpTo(_largeTitleOffset);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.appBar;
    if (!isIos() || header is! IosNativeNavigationBar) {
      return Scaffold(
        appBar: header,
        extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
        body: widget.body,
      );
    }

    // Keep the same coordinator when entering/exiting selection mode so the
    // list's state and scroll position survive the switch to a compact bar.
    return Scaffold(
      body: NestedScrollView(
        key: _scrollKey,
        headerSliverBuilder: (context, _) => [
          if (header.largeTitleMode)
            header.buildSliver(context)
          else
            SliverPersistentHeader(
              pinned: true,
              delegate: _CompactHeaderDelegate(
                header: header,
                height: header.preferredSize.height + MediaQuery.paddingOf(context).top,
              ),
            ),
        ],
        body: widget.body,
      ),
    );
  }
}

class _CompactHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CompactHeaderDelegate({required this.header, required this.height});

  final IosNativeNavigationBar header;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: header);

  @override
  bool shouldRebuild(_CompactHeaderDelegate oldDelegate) =>
      header != oldDelegate.header || height != oldDelegate.height;
}
