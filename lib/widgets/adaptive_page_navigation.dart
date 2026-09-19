import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';

/// Pushes a page using the platform's standard navigation transition.
///
/// iOS intentionally uses Flutter's [CupertinoPageRoute] for standard
/// push/pop geometry, edge-swipe interaction, and reduced-motion behavior.
Future<T?> pushAdaptivePage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
}) =>
    Navigator.of(context).push<T>(adaptivePageRoute<T>(
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
