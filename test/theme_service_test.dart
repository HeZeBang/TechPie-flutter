import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/theme/tp_colors.dart';
import 'package:techpie/theme/tp_tokens.dart';

void main() {
  test('all platforms default to TechRed with grouped neutral surfaces',
      () async {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      debugDefaultTargetPlatformOverride = platform;
      try {
        final themeService = ThemeService(StorageService(preferences));
        expect(themeService.colorScheme, AppColorScheme.techRed);
        expect(themeService.supportsColorSchemeSelection, isTrue);

        final light = themeService.lightTheme;
        final lightTp = light.extension<TpColors>()!;
        expect(light.colorScheme.primary, TpTokens.techRedLight);
        expect(light.scaffoldBackgroundColor, TpTokens.lightCanvas);
        expect(lightTp.canvas, TpTokens.lightCanvas);
        expect(lightTp.surface, TpTokens.lightSurface);
        expect(lightTp.border, Colors.transparent);
        expect(lightTp.brand, TpTokens.techRedLight);

        final dark = themeService.darkTheme;
        final darkTp = dark.extension<TpColors>()!;
        expect(dark.colorScheme.primary, TpTokens.techRedDark);
        expect(dark.scaffoldBackgroundColor, TpTokens.darkCanvas);
        expect(darkTp.canvas, TpTokens.darkCanvas);
        expect(darkTp.surface, TpTokens.darkSurface);
        expect(darkTp.border, TpTokens.darkBorder);
        expect(darkTp.brand, TpTokens.techRedDark);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  test('iOS can opt into System Blue without altering neutral surfaces',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final themeService = ThemeService(StorageService(preferences));
      expect(themeService.usesIosSystemAccent, isTrue);
      expect(themeService.systemDynamicColorAvailable, isTrue);

      await themeService.setColorScheme(AppColorScheme.system);

      final light = themeService.lightTheme;
      final lightTp = light.extension<TpColors>()!;
      expect(light.colorScheme.primary, TpTokens.iosBlueLight);
      expect(lightTp.brand, TpTokens.iosBlueLight);
      expect(lightTp.canvas, TpTokens.lightCanvas);
      expect(lightTp.surface, TpTokens.lightSurface);

      final dark = themeService.darkTheme;
      final darkTp = dark.extension<TpColors>()!;
      expect(dark.colorScheme.primary, TpTokens.iosBlueDark);
      expect(darkTp.brand, TpTokens.iosBlueDark);
      expect(darkTp.canvas, TpTokens.darkCanvas);
      expect(darkTp.surface, TpTokens.darkSurface);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
      'Android dynamic accent only changes brand roles and keeps neutral surfaces',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final themeService = ThemeService(StorageService(preferences));
      final dynamicLight = ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E7D32),
        brightness: Brightness.light,
      );
      final dynamicDark = ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E7D32),
        brightness: Brightness.dark,
      );
      themeService.updateSystemSchemes(dynamicLight, dynamicDark);
      await themeService.setColorScheme(AppColorScheme.system);

      final light = themeService.lightTheme;
      final lightTp = light.extension<TpColors>()!;
      expect(light.colorScheme.primary, dynamicLight.primary);
      expect(lightTp.brand, dynamicLight.primary);
      expect(lightTp.canvas, TpTokens.lightCanvas);
      expect(lightTp.surface, TpTokens.lightSurface);

      final dark = themeService.darkTheme;
      final darkTp = dark.extension<TpColors>()!;
      expect(dark.colorScheme.primary, dynamicDark.primary);
      expect(darkTp.brand, dynamicDark.primary);
      expect(darkTp.canvas, TpTokens.darkCanvas);
      expect(darkTp.surface, TpTokens.darkSurface);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('AMOLED dark mode uses pure black canvas and #141414 cards', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    final themeService = ThemeService(StorageService(preferences));
    await themeService.setMode(AppThemeMode.amoled);

    final amoled = themeService.darkTheme;
    final tp = amoled.extension<TpColors>()!;
    expect(tp.isAmoled, isTrue);
    expect(amoled.scaffoldBackgroundColor, TpTokens.amoledCanvas);
    expect(tp.canvas, TpTokens.amoledCanvas);
    expect(tp.surface, TpTokens.amoledSurface);
    expect(tp.surfaceSubtle, TpTokens.amoledSurfaceSubtle);
    expect(tp.border, TpTokens.amoledBorder);
  });

  test('TpColors copyWith and lerp behave consistently', () {
    final light = TpColors.light();
    final dark = TpColors.dark();

    final custom = light.copyWith(brand: TpTokens.iosBlueLight);
    expect(custom.brand, TpTokens.iosBlueLight);
    expect(custom.canvas, light.canvas);
    expect(custom, isNot(equals(light)));

    expect(light.lerp(dark, 0), light);
    expect(light.lerp(dark, 1), dark);
    final mid = light.lerp(dark, 0.5);
    expect(mid.canvas, Color.lerp(light.canvas, dark.canvas, 0.5));
    expect(mid.brand, Color.lerp(light.brand, dark.brand, 0.5));
  });
}
