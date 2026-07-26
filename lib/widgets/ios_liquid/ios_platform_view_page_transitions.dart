import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/platform.dart';

/// Pushes a page using the platform's standard navigation transition.
///
/// iOS intentionally uses Flutter's [CupertinoPageRoute]. It implements the
/// same push/pop geometry, edge-swipe interaction, and reduced-motion behavior
/// as the rest of Flutter's Cupertino navigation stack without maintaining a
/// second snapshot stack in UIKit.
Future<T?> pushPlatformViewPage<T>(
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
Future<bool> maybePopPlatformViewPage<T>(
  BuildContext context, [
  T? result,
]) {
  return Navigator.of(context).maybePop<T>(result);
}
