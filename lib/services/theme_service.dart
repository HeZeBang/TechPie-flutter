import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'storage_service.dart';

enum AppThemeMode {
  system('System', Icons.brightness_auto_outlined),
  light('Light', Icons.light_mode_outlined),
  dark('Dark', Icons.dark_mode_outlined),
  amoled('Dark AMOLED', Icons.brightness_2_outlined);

  const AppThemeMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ThemeService extends ChangeNotifier {
  static const _seed = Colors.deepPurple;
  static const _iosLightAccent = Color(0xFF007AFF);
  static const _iosDarkAccent = Color(0xFF0A84FF);
  static const _iosLightBackground = Color(0xFFFFFFFF);
  static const _iosLightSurface = Color(0xFFF2F2F7);
  static const _iosLightSurfaceHigh = Color(0xFFE5E5EA);
  static const _iosLightSurfaceHighest = Color(0xFFD1D1D6);
  static const _iosLightPrimaryContainer = Color(0xFFDCEBFF);
  static const _iosLightSecondaryContainer = Color(0xFFFFFFFF);
  static const _iosLightTertiary = Color(0xFF34C759);
  static const _iosLightTertiaryContainer = Color(0xFFD9F7E1);
  static const _iosDarkBackground = Color(0xFF000000);
  static const _iosDarkSurface = Color(0xFF1C1C1E);
  static const _iosDarkSurfaceHigh = Color(0xFF2C2C2E);
  static const _iosDarkSurfaceHighest = Color(0xFF3A3A3C);
  static const _iosDarkPrimaryContainer = Color(0xFF0E2F57);
  static const _iosDarkSecondaryContainer = Color(0xFF2C2C2E);
  static const _iosDarkTertiary = Color(0xFF30D158);
  static const _iosDarkTertiaryContainer = Color(0xFF163824);

  final StorageService _storage;

  ThemeService(this._storage)
    : _mode = AppThemeMode.values.firstWhere(
        (m) => m.name == _storage.themeMode,
        orElse: () => AppThemeMode.system,
      );

  AppThemeMode _mode;
  AppThemeMode get mode => _mode;

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _storage.setThemeMode(mode.name);
  }

  ThemeMode get themeMode {
    switch (_mode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
      case AppThemeMode.amoled:
        return ThemeMode.dark;
    }
  }

  bool get _usesIosTheme =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed),
    );

    if (!_usesIosTheme) {
      return _buildDesktopTheme(base);
    }

    return _buildIosTheme(base, brightness: Brightness.light);
  }

  ThemeData get darkTheme {
    final base = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );

    if (_mode == AppThemeMode.amoled) {
      if (_usesIosTheme) {
        return _buildIosTheme(
          ThemeData(useMaterial3: true, colorScheme: base),
          brightness: Brightness.dark,
          amoled: true,
        );
      }

      return ThemeData(
        useMaterial3: true,
        colorScheme: base.copyWith(
          surface: Colors.black,
          onSurface: Colors.white,
          surfaceContainerLowest: Colors.black,
          surfaceContainerLow: const Color(0xFF0A0A0A),
          surfaceContainer: const Color(0xFF121212),
          surfaceContainerHigh: const Color(0xFF1A1A1A),
          surfaceContainerHighest: const Color(0xFF222222),
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(centerTitle: false),
      );
    }

    final theme = ThemeData(useMaterial3: true, colorScheme: base);

    if (!_usesIosTheme) {
      return _buildDesktopTheme(theme);
    }

    return _buildIosTheme(theme, brightness: Brightness.dark);
  }

  ThemeData _buildDesktopTheme(ThemeData base) {
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(centerTitle: false),
    );
  }

  ThemeData _buildIosTheme(
    ThemeData base, {
    required Brightness brightness,
    bool amoled = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? _iosDarkBackground : _iosLightBackground;
    final surface = amoled
        ? Colors.black
        : isDark
        ? _iosDarkSurface
        : _iosLightSurface;
    final surfaceHigh = amoled
        ? const Color(0xFF101012)
        : isDark
        ? _iosDarkSurfaceHigh
        : _iosLightSurfaceHigh;
    final surfaceHighest = amoled
        ? const Color(0xFF1C1C1E)
        : isDark
        ? _iosDarkSurfaceHighest
        : _iosLightSurfaceHighest;
    final scheme = base.colorScheme.copyWith(
      primary: isDark ? _iosDarkAccent : _iosLightAccent,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? _iosDarkPrimaryContainer
          : _iosLightPrimaryContainer,
      onPrimaryContainer: isDark
          ? const Color(0xFFD7E8FF)
          : const Color(0xFF001B3D),
      secondary: isDark ? _iosDarkAccent : _iosLightAccent,
      onSecondary: Colors.white,
      secondaryContainer: isDark
          ? _iosDarkSecondaryContainer
          : _iosLightSecondaryContainer,
      onSecondaryContainer: isDark ? Colors.white : Colors.black,
      tertiary: isDark ? _iosDarkTertiary : _iosLightTertiary,
      onTertiary: Colors.white,
      tertiaryContainer: isDark
          ? _iosDarkTertiaryContainer
          : _iosLightTertiaryContainer,
      onTertiaryContainer: isDark
          ? const Color(0xFFD9F7E1)
          : const Color(0xFF11361D),
      surface: background,
      onSurface: isDark ? Colors.white : Colors.black,
      surfaceDim: surface,
      surfaceBright: background,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHighest,
      onSurfaceVariant: isDark
          ? const Color(0xFFAEAEB2)
          : const Color(0xFF6C6C70),
      outline: isDark ? const Color(0x3DEBEBF5) : const Color(0x4C3C3C43),
      outlineVariant: isDark
          ? const Color(0x24EBEBF5)
          : const Color(0x1F3C3C43),
      surfaceTint: Colors.transparent,
    );

    return base.copyWith(
      platform: TargetPlatform.iOS,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: isDark ? Colors.white : Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHighest,
        contentTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
      ),
    );
  }
}
