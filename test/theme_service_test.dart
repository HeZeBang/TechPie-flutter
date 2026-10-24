import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/theme_service.dart';

void main() {
  test('iOS keeps a consistent system tint across Flutter and UIKit', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final themeService = ThemeService(StorageService(preferences));

      expect(themeService.supportsColorSchemeSelection, isFalse);
      expect(
        themeService.lightTheme.colorScheme.primary,
        const Color(0xFF007AFF),
      );

      await themeService.setColorScheme(AppColorScheme.techRed);
      expect(
        themeService.lightTheme.colorScheme.primary,
        const Color(0xFF007AFF),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('glass mode persists and drives the theme extension on Android',
      () async {
    SharedPreferences.setMockInitialValues({'glass_mode': 'liquid'});
    final preferences = await SharedPreferences.getInstance();

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final storage = StorageService(preferences);
      final themeService = ThemeService(storage);

      expect(themeService.supportsGlassModeSelection, isTrue);
      expect(themeService.glassMode, AppGlassMode.liquid);
      expect(
        themeService.lightTheme.extension<GlassTheme>()?.mode,
        AppGlassMode.liquid,
      );

      await themeService.setGlassMode(AppGlassMode.classic);
      expect(ThemeService(storage).glassMode, AppGlassMode.classic);
      expect(
        themeService.darkTheme.extension<GlassTheme>()?.mode,
        AppGlassMode.classic,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('other platforms cannot pick a glass mode and stay frosted', () async {
    SharedPreferences.setMockInitialValues({'glass_mode': 'liquid'});
    final preferences = await SharedPreferences.getInstance();

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final themeService = ThemeService(StorageService(preferences));

      expect(themeService.supportsGlassModeSelection, isFalse);
      expect(
        themeService.darkTheme.extension<GlassTheme>()?.mode,
        AppGlassMode.frosted,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
