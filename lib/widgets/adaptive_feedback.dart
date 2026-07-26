import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/platform.dart';
import 'app_shell/tg_bottom_nav_bar.dart';

final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

final GlobalKey<AdaptiveFeedbackHostState> adaptiveFeedbackHostKey =
    GlobalKey<AdaptiveFeedbackHostState>();

/// Tracks how many page routes are stacked above the shell so the feedback
/// banner knows whether the bottom nav is on screen. Dialog/popup routes
/// don't count — the nav stays visible underneath them.
final ValueNotifier<int> _pageRouteDepth = ValueNotifier<int>(0);

class FeedbackRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _pageRouteDepth.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _pageRouteDepth.value--;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _pageRouteDepth.value--;
  }
}

enum AdaptiveFeedbackStyle { info, success, error }

void showAdaptiveFeedback({
  BuildContext? context,
  required String message,
  AdaptiveFeedbackStyle style = AdaptiveFeedbackStyle.info,
  Duration duration = const Duration(seconds: 3),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  adaptiveFeedbackHostKey.currentState?.show(
    message: message,
    style: style,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// App-level host for feedback banners, mounted above the [Navigator] (via
/// `MaterialApp.builder`).
///
/// A [SnackBar] can't be used here: the root [ScaffoldMessenger] renders the
/// current snackbar in BOTH the outgoing and incoming route's Scaffold during
/// a page transition, and since pages with and without the bottom nav give it
/// different bottom offsets, the same bar briefly shows twice ("ghosting").
/// Hosting a single banner above the Navigator means there is exactly one
/// instance, and its bottom clearance simply animates in step with the route
/// transition: flush-ish near the screen edge on pushed pages, floating above
/// the glass capsule (with a larger corner radius) on shell pages.
class AdaptiveFeedbackHost extends StatefulWidget {
  final Widget child;

  const AdaptiveFeedbackHost({super.key, required this.child});

  @override
  State<AdaptiveFeedbackHost> createState() => AdaptiveFeedbackHostState();
}

class AdaptiveFeedbackHostState extends State<AdaptiveFeedbackHost>
    with SingleTickerProviderStateMixin {
  // Matches the FadeThroughTransition page-transition timing so the banner
  // glides together with the bottom nav's appearance.
  static const _repositionDuration = Duration(milliseconds: 300);
  static const _repositionCurve = Curves.easeInOutCubic;

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  _FeedbackEntry? _entry;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    // The host is (re)built before the Navigator pushes its initial route
    // (fresh start and hot restart alike), so the route count starts clean.
    _pageRouteDepth.value = 0;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(_fade);
  }

  void show({
    required String message,
    required AdaptiveFeedbackStyle style,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _dismissTimer?.cancel();
    setState(() {
      _entry = _FeedbackEntry(
        message: message,
        style: style,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    });
    _controller.forward(from: _controller.value == 0 ? 0 : _controller.value);
    _dismissTimer = Timer(duration, dismiss);
  }

  void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    unawaited(
      _controller.reverse().whenComplete(() {
        if (mounted && _dismissTimer == null) setState(() => _entry = null);
      }),
    );
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_entry != null)
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: _pageRouteDepth,
              builder: (context, depth, banner) {
                final width = MediaQuery.sizeOf(context).width;
                final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
                final navVisible = depth <= 1 && width < 600;
                final navClearance = isIos()
                    ? 52.0 + 12
                    : TgBottomNavBar.barHeight + 2 * TgBottomNavBar.margin;
                final bottom = safeBottom + (navVisible ? navClearance : 12);
                return IgnorePointer(
                  ignoring: _entry!.actionLabel == null,
                  child: AnimatedPadding(
                    duration: _repositionDuration,
                    curve: _repositionCurve,
                    padding: EdgeInsets.fromLTRB(12, 0, 12, bottom),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FadeTransition(
                        opacity: _fade,
                        child: SlideTransition(
                          position: _slide,
                          child: _FeedbackBanner(
                            entry: _entry!,
                            rounded: navVisible,
                            repositionDuration: _repositionDuration,
                            repositionCurve: _repositionCurve,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _FeedbackEntry {
  const _FeedbackEntry({
    required this.message,
    required this.style,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AdaptiveFeedbackStyle style;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({
    required this.entry,
    required this.rounded,
    required this.repositionDuration,
    required this.repositionCurve,
  });

  final _FeedbackEntry entry;
  final bool rounded;
  final Duration repositionDuration;
  final Curve repositionCurve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _FeedbackStyle.from(theme, entry.style);
    final radius = BorderRadius.circular(rounded ? 16 : 10);

    return AnimatedContainer(
      duration: repositionDuration,
      curve: repositionCurve,
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: radius,
        boxShadow: kElevationToShadow[6],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.foregroundColor),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              entry.message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: style.foregroundColor),
            ),
          ),
          if (entry.actionLabel != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                entry.onAction?.call();
                adaptiveFeedbackHostKey.currentState?.dismiss();
              },
              child: Text(entry.actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackStyle {
  const _FeedbackStyle({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;

  static _FeedbackStyle from(ThemeData theme, AdaptiveFeedbackStyle style) {
    final colors = theme.colorScheme;

    return switch (style) {
      AdaptiveFeedbackStyle.success => _FeedbackStyle(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          icon: Icons.check_circle_outline,
        ),
      AdaptiveFeedbackStyle.error => _FeedbackStyle(
          backgroundColor: colors.errorContainer,
          foregroundColor: colors.onErrorContainer,
          icon: Icons.error_outline,
        ),
      AdaptiveFeedbackStyle.info => _FeedbackStyle(
          backgroundColor: colors.inverseSurface,
          foregroundColor: colors.onInverseSurface,
          icon: Icons.info_outline,
        ),
    };
  }
}
