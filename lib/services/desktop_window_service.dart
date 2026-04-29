import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowService with WindowListener {
  DesktopWindowService(this._prefs);

  static const String _widthKey = 'desktop_window_width';
  static const String _heightKey = 'desktop_window_height';

  static const Size _defaultSize = Size(1280, 720);

  final SharedPreferences _prefs;
  Timer? _saveDebounce;

  static bool get isDesktop {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  Future<void> initialize() async {
    if (!isDesktop) return;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;

    final windowOptions = WindowOptions(
      size: _initialSize,
      center: true,
      title: 'TechPie',
      titleBarStyle:
          isMacOS ? TitleBarStyle.hidden : TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  Size get _initialSize {
    final savedWidth = _prefs.getDouble(_widthKey);
    final savedHeight = _prefs.getDouble(_heightKey);
    if (savedWidth == null || savedHeight == null) {
      return _defaultSize;
    }

    if (!_isUsableDimension(savedWidth) || !_isUsableDimension(savedHeight)) {
      return _defaultSize;
    }

    return Size(savedWidth, savedHeight);
  }

  bool _isUsableDimension(double value) {
    return value.isFinite && !value.isNaN && value > 0;
  }

  @override
  void onWindowResize() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _saveSize);
  }

  @override
  void onWindowResized() {
    _saveDebounce?.cancel();
    _saveSize();
  }

  Future<void> _saveSize() async {
    final size = await windowManager.getSize();
    if (!_isUsableDimension(size.width) || !_isUsableDimension(size.height)) {
      return;
    }

    await _prefs.setDouble(_widthKey, size.width);
    await _prefs.setDouble(_heightKey, size.height);
  }
}
