import 'package:flutter/widgets.dart';

/// Marks interactive web content below it as unable to receive pointer or
/// wheel input while a surface owned by the workspace (the history drawer)
/// covers it.
///
/// A Flutter barrier cannot intercept input that lands in a platform view's
/// own document, so the web visual surface switches its DOM host and iframe
/// off while this flag is set. Modal routes above the workspace do not need
/// this scope: the surface detects them itself through
/// `ModalRoute.isCurrentOf`, which also covers dialogs, sheets and menus
/// opened from outside the workspace.
///
/// The scope is platform neutral. Native surfaces never consult it, so adding
/// it to the workspace changes nothing off the web.
class GenAiWebInputScope extends InheritedWidget {
  const GenAiWebInputScope({
    super.key,
    required this.blocked,
    required super.child,
  });

  /// Whether interactive web content below should stop receiving input.
  final bool blocked;

  /// Whether an ancestor scope asked web content to stop receiving input.
  /// Missing scopes never block, so the surface can be hosted on its own.
  static bool blockedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GenAiWebInputScope>()?.blocked ?? false;

  /// Whether interactive web content hosted at [context] must stop receiving
  /// input: an ancestor scope is blocked, or a modal route (dialog, sheet,
  /// menu) covers the route that hosts [context]. The two sources combine, so
  /// closing one never re-enables input while the other is still open. A
  /// context outside a modal route is never blocked by route state.
  ///
  /// Both reads register dependencies, so the calling widget rebuilds when
  /// either surface opens or closes.
  static bool blocks(BuildContext context) {
    // Resolve both sources even when the first one already blocks, so the
    // route dependency is never skipped by short-circuiting.
    final scopeBlocked = blockedOf(context);
    final routeBlocked = ModalRoute.isCurrentOf(context) == false;
    return scopeBlocked || routeBlocked;
  }

  @override
  bool updateShouldNotify(GenAiWebInputScope oldWidget) => blocked != oldWidget.blocked;
}
