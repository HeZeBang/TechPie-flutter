import 'package:flutter/widgets.dart';

/// Marks the full app subtree as hidden behind the glance surface.
///
/// The shell reads this from an event handler (a pending eCard entry), where
/// registering an inherited dependency is not appropriate, so [isActive] is a
/// non-subscribing lookup.
class GlanceActiveScope extends InheritedWidget {
  const GlanceActiveScope({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  static GlanceActiveScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlanceActiveScope>();

  static bool isActive(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GlanceActiveScope>()?.active ??
      false;

  @override
  bool updateShouldNotify(GlanceActiveScope oldWidget) =>
      oldWidget.active != active;
}
