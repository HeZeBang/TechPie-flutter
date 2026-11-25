import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    this.clipBodyBelowAppBar = false,
  });

  final PreferredSizeWidget appBar;
  final Widget body;
  final bool extendBodyBehindAppBar;

  /// Clip iOS platform views in the body before the pinned bar is painted.
  final bool clipBodyBelowAppBar;

  /// Whether non-iOS app bars blur behind scrolling body content.
  static bool extendsBodyBehindAppBar() => !isIos() && !usesLegacyIosChrome();

  /// Top content inset reserved below a blurred app bar on non-iOS platforms.
  static double contentTopInsetOf(
    BuildContext context, {
    double extra = 0,
  }) =>
      (isIos() || usesLegacyIosChrome())
          ? extra
          : extra + adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

  /// Selects the platform-appropriate top navigation bar without leaking
  /// platform branches into page files.
  static PreferredSizeWidget adaptiveBar({
    required PreferredSizeWidget Function() ios,
    required PreferredSizeWidget Function() material,
  }) =>
      isIos() ? ios() : material();

  /// Chooses between iOS and non-iOS platform chrome widgets (e.g. sheet
  /// action buttons or inline selectors) while keeping page code platform-clean.
  static Widget adaptiveChrome({
    required Widget Function() ios,
    required Widget Function() material,
  }) =>
      isIos() ? ios() : material();

  /// Shows a platform-appropriate modal bottom sheet with matching grabber and
  /// top padding conventions.
  static Future<T?> showSheet<T>({
    required BuildContext context,
    required Widget Function(BuildContext context, EdgeInsets contentPadding)
        builder,
    bool useRootNavigator = true,
  }) {
    final ios = isIos();
    return CNBottomSheet.show<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      showDragHandle: !ios,
      builder: (sheetContext) => builder(
        sheetContext,
        EdgeInsets.fromLTRB(24, ios ? 28 : 0, 24, 32),
      ),
    );
  }

  @override
  State<AdaptiveNavigationScaffold> createState() => _AdaptiveNavigationScaffoldState();
}

class _AdaptiveNavigationScaffoldState extends State<AdaptiveNavigationScaffold> {
  final _scrollKey = GlobalKey<NestedScrollViewState>();
  final _headerKey = GlobalKey();
  final _bodyClipKey = GlobalKey();
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
          KeyedSubtree(
            key: _headerKey,
            child: header.largeTitleMode
                ? header.buildSliver(context)
                : SliverPersistentHeader(
                    pinned: true,
                    delegate: _CompactHeaderDelegate(
                      header: header,
                      height: header.preferredSize.height +
                          MediaQuery.paddingOf(context).top,
                    ),
                  ),
          ),
        ],
        body: widget.clipBodyBelowAppBar
            ? Builder(
                builder: (context) => ClipRect(
                  key: _bodyClipKey,
                  clipper: _PinnedHeaderClipper(
                    headerKey: _headerKey,
                    bodyKey: _bodyClipKey,
                    scrollPosition: Scrollable.of(context).position,
                  ),
                  child: widget.body,
                ),
              )
            : widget.body,
      ),
    );
  }
}

class _PinnedHeaderClipper extends CustomClipper<Rect> {
  _PinnedHeaderClipper({
    required this.headerKey,
    required this.bodyKey,
    required ScrollPosition scrollPosition,
  }) : super(reclip: scrollPosition);

  final GlobalKey headerKey;
  final GlobalKey bodyKey;

  @override
  Rect getClip(Size size) {
    final header = headerKey.currentContext!.findRenderObject()! as RenderSliver;
    final body = bodyKey.currentContext!.findRenderObject()!;
    final bottom = MatrixUtils.transformPoint(
      header.getTransformTo(body),
      Offset(0, header.geometry!.paintExtent),
    ).dy;
    // UIKit paints the glass even where the Flutter bar covers the scrolling
    // body. Clip the body in its own coordinates as the two begin overlapping.
    return Rect.fromLTRB(
      0,
      bottom.clamp(0.0, size.height),
      size.width,
      size.height,
    );
  }

  @override
  Rect getApproximateClipRect(Size size) => getClip(size);

  @override
  bool shouldReclip(_PinnedHeaderClipper oldClipper) => true;
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
