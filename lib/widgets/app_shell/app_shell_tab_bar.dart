import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lets a page inside a tab take the tab bar's place for a while.
///
/// Photos, Files and Mail do this while selecting: the tab bar goes away and a
/// toolbar with the selection's actions sits where it was, rather than a second
/// bar stacked above it. A page asks with [hide] when it enters that mode and
/// releases the hold when it leaves (or is disposed); the bar returns once no
/// page holds it.
class AppShellTabBarController extends ChangeNotifier {
  int _holds = 0;

  /// Whether some page is standing in for the tab bar.
  bool get hidden => _holds > 0;

  /// Hides the tab bar until the returned hold is released. Safe to call
  /// while the tree is building (didChangeDependencies): the shell rebuilds
  /// on the next frame then.
  AppShellTabBarHold hide() {
    _holds++;
    if (_holds == 1) _notify();
    return AppShellTabBarHold._(this);
  }

  void _release() {
    if (_holds == 0) return;
    _holds--;
    if (_holds == 0) _notify();
  }

  void _notify() {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One page's claim on the tab bar's place. Releasing it twice is harmless.
class AppShellTabBarHold {
  AppShellTabBarHold._(this._controller);

  AppShellTabBarController? _controller;

  void release() {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    controller._release();
  }
}

/// Provides the shell's [AppShellTabBarController] to the pages in its tabs.
class AppShellTabBar extends InheritedWidget {
  const AppShellTabBar({
    super.key,
    required this.controller,
    required super.child,
  });

  final AppShellTabBarController controller;

  /// The shell's controller, or null outside the shell (a page pushed on the
  /// root navigator, a test) — where there is no tab bar to hide.
  static AppShellTabBarController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppShellTabBar>()?.controller;

  @override
  bool updateShouldNotify(AppShellTabBar oldWidget) =>
      controller != oldWidget.controller;
}
