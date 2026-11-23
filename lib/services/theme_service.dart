import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tp_colors.dart';
import '../theme/tp_tokens.dart';
import '../theme/tp_typography.dart';
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

enum AppColorScheme {
  techRed('TechRed', Icons.palette_outlined),
  system('System', Icons.colorize_outlined);

  const AppColorScheme(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ThemeService extends ChangeNotifier {
  final StorageService _storage;

  ThemeService(this._storage)
      : _mode = AppThemeMode.values.firstWhere(
          (m) => m.name == _storage.themeMode,
          orElse: () => AppThemeMode.system,
        ),
        _colorScheme = AppColorScheme.values.firstWhere(
          (s) => s.name == _storage.colorScheme,
          orElse: () => AppColorScheme.techRed,
        );

  AppThemeMode _mode;
  AppThemeMode get mode => _mode;

  AppColorScheme _colorScheme;
  AppColorScheme get colorScheme => _colorScheme;

  ColorScheme? _systemLight;
  ColorScheme? _systemDark;

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _storage.setThemeMode(mode.name);
  }

  Future<void> setColorScheme(AppColorScheme scheme) async {
    if (_colorScheme == scheme) return;
    _colorScheme = scheme;
    notifyListeners();
    await _storage.setColorScheme(scheme.name);
  }

  void updateSystemSchemes(ColorScheme? light, ColorScheme? dark) {
    if (_systemLight == light && _systemDark == dark) return;
    _systemLight = light;
    _systemDark = dark;
    notifyListeners();
  }

  bool get _usesIosTheme =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// On iOS, `AppColorScheme.system` resolves to Apple System Blue.
  bool get usesIosSystemAccent => _usesIosTheme;

  bool get systemDynamicColorAvailable =>
      _usesIosTheme || _systemLight != null || _systemDark != null;

  bool get supportsColorSchemeSelection => true;

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

  ThemeData get lightTheme => _buildTheme(Brightness.light);

  ThemeData get darkTheme =>
      _buildTheme(Brightness.dark, amoled: _mode == AppThemeMode.amoled);

  /// Snackbars float as rounded cards above the glass bottom nav (which is a
  /// 56dp capsule with 8dp margins) instead of a full-width strip glued to it.
  static const _snackBarShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(TpTokens.radiusM)),
  );
  static const _snackBarInsets = EdgeInsets.fromLTRB(12, 0, 12, 12);

  ({Color? accent, Color? onAccent}) _resolveAccent(Brightness brightness) {
    if (_colorScheme != AppColorScheme.system) {
      return (accent: null, onAccent: null);
    }
    final isDark = brightness == Brightness.dark;
    if (_usesIosTheme) {
      return (
        accent: isDark ? TpTokens.iosBlueDark : TpTokens.iosBlueLight,
        onAccent: Colors.white,
      );
    }
    final system = isDark ? _systemDark : _systemLight;
    if (system != null) {
      return (accent: system.primary, onAccent: system.onPrimary);
    }
    return (accent: null, onAccent: null);
  }

  ThemeData _buildTheme(Brightness brightness, {bool amoled = false}) {
    final isDark = brightness == Brightness.dark;
    final resolved = _resolveAccent(brightness);
    final tp = isDark
        ? TpColors.dark(
            amoled: amoled,
            accent: resolved.accent,
            onAccent: resolved.onAccent,
          )
        : TpColors.light(
            accent: resolved.accent,
            onAccent: resolved.onAccent,
          );
    final scheme = tp.toColorScheme();
    final cardBorder = tp.border == Colors.transparent
        ? BorderSide.none
        : BorderSide(color: tp.border);

    return ThemeData(
      useMaterial3: true,
      platform: _usesIosTheme ? TargetPlatform.iOS : null,
      fontFamilyFallback: TpTypography.fontFamilyFallback,
      colorScheme: scheme,
      scaffoldBackgroundColor: tp.canvas,
      canvasColor: tp.canvas,
      cardColor: tp.surface,
      dividerColor: tp.divider,
      dividerTheme: DividerThemeData(
        color: tp.divider,
        thickness: 0.5,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: tp.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(TpTokens.radiusM),
          ),
          side: cardBorder,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tp.canvas,
        foregroundColor: tp.textPrimary,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tp.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TpTokens.radiusL),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tp.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(TpTokens.radiusL)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? tp.surfacePressed : null,
        contentTextStyle: isDark ? TextStyle(color: tp.textPrimary) : null,
        behavior: SnackBarBehavior.floating,
        shape: _snackBarShape,
        insetPadding: _snackBarInsets,
      ),
      inputDecorationTheme: _usesIosTheme
          ? InputDecorationTheme(
              filled: true,
              fillColor: tp.surface,
            )
          : null,
      extensions: <ThemeExtension<dynamic>>[tp],
    );
  }
}
