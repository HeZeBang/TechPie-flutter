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
}
