import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';

/// Pushes a page using the platform's standard navigation transition.
///
/// iOS intentionally uses Flutter's [CupertinoPageRoute] for standard
/// push/pop geometry, edge-swipe interaction, and reduced-motion behavior.
///
/// A page lands in the nearest stack — on iOS that is the selected tab's, so
/// the tab bar stays. [rootNavigator] is for a page that takes over the whole
/// app instead (a self-contained feature, a full-screen player), which is the
/// only place a page may cover the tab bar.
Future<T?> pushAdaptivePage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool rootNavigator = false,
}) =>
    Navigator.of(context, rootNavigator: rootNavigator)
        .push<T>(adaptivePageRoute<T>(
      builder: builder,
      settings: settings,
    ),);

/// The route a page gets on this platform. Exposed so a subtree that owns its
/// own navigator (a feature with its own page stack) can push pages that look and
/// behave exactly like the host's, instead of inventing a transition policy.
Route<T> adaptivePageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) =>
    isIos()
        ? CupertinoPageRoute<T>(settings: settings, builder: builder)
        : MaterialPageRoute<T>(settings: settings, builder: builder);

/// Pops the current page through the active platform route.
Future<bool> maybePopAdaptivePage<T>(
  BuildContext context, [
  T? result,
]) {
  return Navigator.of(context).maybePop<T>(result);
}
