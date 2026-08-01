import 'package:flutter/widgets.dart';

class AppShellMetrics extends InheritedWidget {
  const AppShellMetrics({
    super.key,
    required this.bottomObstruction,
    required super.child,
  });

  final double bottomObstruction;

  static double bottomContentPaddingOf(
    BuildContext context, {
    double margin = 16,
  }) {
    final metrics =
        context.dependOnInheritedWidgetOfExactType<AppShellMetrics>();
    final obstruction =
        metrics?.bottomObstruction ?? MediaQuery.viewPaddingOf(context).bottom;
    return obstruction + margin;
  }

  @override
  bool updateShouldNotify(AppShellMetrics oldWidget) {
    return bottomObstruction != oldWidget.bottomObstruction;
  }
}
