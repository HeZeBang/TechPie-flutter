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
}) {
  final navigator = Navigator.of(context);
  final route = isIos()
      ? CupertinoPageRoute<T>(settings: settings, builder: builder)
      : MaterialPageRoute<T>(settings: settings, builder: builder);

  return navigator.push<T>(route);
}

/// Pops the current page through the active platform route.
Future<bool> maybePopAdaptivePage<T>(
  BuildContext context, [
  T? result,
]) {
  return Navigator.of(context).maybePop<T>(result);
}
