import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Top clearance reserved for macOS traffic-light window controls inside the
/// integrated transparent titlebar.
const double macOsTitlebarInset = 28;

const MethodChannel _windowChromeChannel = MethodChannel('techpie/window_chrome');

bool isMacOsDesktop() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Initiates native window dragging from a custom titlebar/sidebar header region
/// on macOS. Safely no-ops on other platforms or in headless tests.
Future<void> startMacOsWindowDrag() async {
  if (!isMacOsDesktop()) return;
  try {
    await _windowChromeChannel.invokeMethod<void>('startDrag');
  } on MissingPluginException {
    // Headless widget tests and non-macOS hosts do not register window chrome.
  } on PlatformException {
    // Ignore transient window-server rejections.
  }
}

/// Toggles native macOS window zoom when double-clicking the titlebar drag zone.
Future<void> toggleMacOsWindowZoom() async {
  if (!isMacOsDesktop()) return;
  try {
    await _windowChromeChannel.invokeMethod<void>('toggleZoom');
  } on MissingPluginException {
    // Headless widget tests and non-macOS hosts do not register window chrome.
  } on PlatformException {
    // Ignore transient window-server rejections.
  }
}

/// Wraps blank chrome areas on macOS so dragging moves the window and
/// double-clicking zooms, while remaining a transparent pass-through elsewhere.
class MacOsWindowDragRegion extends StatelessWidget {
  const MacOsWindowDragRegion({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isMacOsDesktop()) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => unawaited(startMacOsWindowDrag()),
      onDoubleTap: () => unawaited(toggleMacOsWindowZoom()),
      child: child,
    );
  }
}
