import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tp_colors.dart';
import '../theme/tp_icons.dart';
import '../theme/tp_tokens.dart';
import '../theme/tp_typography.dart';
import 'storage_service.dart';

enum AppThemeMode {
  system('跟随系统', TpIcons.smartphone),
  light('浅色', TpIcons.sun),
  dark('深色', TpIcons.moon),
  amoled('纯黑 AMOLED', TpIcons.amoled);

  const AppThemeMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum AppColorScheme {
  techRed('科技红 · TechRed', TpIcons.palette),
  system('跟随系统', TpIcons.sparkles);

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
    if (_colorScheme == AppColorScheme.system) {
      notifyListeners();
    }
  }

  bool get _usesIosTheme =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// On iOS, `AppColorScheme.system` resolves to Apple System Blue.
  bool get usesIosSystemAccent => _usesIosTheme;

  bool get systemDynamicColorAvailable =>
      _usesIosTheme || _systemLight != null || _systemDark != null;

  bool get supportsColorSchemeSelection => true;

  /// Human-readable label for [scheme] on the current platform.
  String colorSchemeLabel(AppColorScheme scheme) {
    if (scheme == AppColorScheme.system && usesIosSystemAccent) {
      return '系统蓝';
    }
    return scheme.label;
  }

  /// Swatch color representing [scheme] under [brightness] for picker previews.
  Color previewColorForScheme(AppColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    if (scheme == AppColorScheme.system) {
      if (_usesIosTheme) {
        return isDark ? TpTokens.iosBlueDark : TpTokens.iosBlueLight;
      }
      final dynamicScheme = isDark ? _systemDark : _systemLight;
      if (dynamicScheme != null) return dynamicScheme.primary;
    }
    return isDark ? TpTokens.techRedDark : TpTokens.techRedLight;
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
    final dialogShape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(Radius.circular(TpTokens.radiusL)),
      side: cardBorder,
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(TpTokens.radiusS),
      borderSide: BorderSide(
        color: isDark ? tp.border : scheme.outline.withValues(alpha: 0.45),
      ),
    );
    final iosInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(TpTokens.radiusS),
      borderSide: BorderSide(
        color: isDark ? tp.border : tp.divider,
        width: 0.75,
      ),
    );
    final iosFocusedInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(TpTokens.radiusS),
      borderSide: BorderSide(color: tp.brand, width: 1.25),
    );
    final iosErrorInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(TpTokens.radiusS),
      borderSide: BorderSide(color: tp.dangerRed, width: 1.0),
    );

    return ThemeData(
      useMaterial3: true,
      platform: _usesIosTheme ? TargetPlatform.iOS : null,
      fontFamilyFallback: TpTypography.fontFamilyFallback,
      colorScheme: scheme,
      primaryColor: tp.brand,
      primaryColorLight: scheme.primaryContainer,
      primaryColorDark: tp.brand,
      secondaryHeaderColor: scheme.primaryContainer,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: tp.brand,
        primaryContrastingColor: tp.onBrand,
        barBackgroundColor: tp.canvas,
        scaffoldBackgroundColor: tp.canvas,
        applyThemeToAll: true,
      ),
      scaffoldBackgroundColor: tp.canvas,
      canvasColor: tp.surface,
      cardColor: tp.surface,
      dividerColor: tp.divider,
      splashFactory: _usesIosTheme ? NoSplash.splashFactory : null,
      splashColor: _usesIosTheme ? Colors.transparent : null,
      highlightColor: _usesIosTheme
          ? tp.surfacePressed.withValues(alpha: isDark ? 0.85 : 0.90)
          : null,
      filledButtonTheme: _usesIosTheme
          ? FilledButtonThemeData(
              style: ButtonStyle(
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.18);
                  }
                  return null;
                }),
              ),
            )
          : null,
      outlinedButtonTheme: _usesIosTheme
          ? OutlinedButtonThemeData(
              style: ButtonStyle(
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return tp.brand.withValues(alpha: isDark ? 0.22 : 0.14);
                  }
                  return null;
                }),
              ),
            )
          : null,
      textButtonTheme: _usesIosTheme
          ? TextButtonThemeData(
              style: ButtonStyle(
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return tp.brand.withValues(alpha: isDark ? 0.22 : 0.14);
                  }
                  return null;
                }),
              ),
            )
          : null,
      iconButtonTheme: _usesIosTheme
          ? IconButtonThemeData(
              style: ButtonStyle(
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return tp.textPrimary
                        .withValues(alpha: isDark ? 0.18 : 0.12);
                  }
                  return null;
                }),
              ),
            )
          : null,
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
        shape: dialogShape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tp.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius:
              const BorderRadius.all(Radius.circular(TpTokens.radiusM)),
          side: BorderSide(color: isDark ? tp.border : tp.divider),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? tp.surfacePressed : scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: isDark ? tp.textPrimary : scheme.onInverseSurface,
        ),
        actionTextColor: isDark ? tp.brandInk : scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: _snackBarShape,
        insetPadding: _snackBarInsets,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tp.surface,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        disabledColor: tp.surfaceSubtle,
        checkmarkColor: tp.brandInk,
        deleteIconColor: tp.textMuted,
        surfaceTintColor: Colors.transparent,
        labelStyle: TextStyle(
          color: tp.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          color: tp.brandInk,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(
              color: tp.brand.withValues(alpha: isDark ? 0.52 : 0.35),
            );
          }
          return BorderSide(
            color: isDark ? tp.border : scheme.outline.withValues(alpha: 0.45),
          );
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TpTokens.radiusS),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primaryContainer;
            }
            return tp.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tp.textMuted.withValues(alpha: 0.5);
            }
            if (states.contains(WidgetState.selected)) {
              return tp.brandInk;
            }
            return tp.textPrimary;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return tp.brandInk;
            }
            return tp.textMuted;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(
                color: tp.brand.withValues(alpha: isDark ? 0.50 : 0.35),
              );
            }
            return BorderSide(
              color: isDark ? tp.border : scheme.outline.withValues(alpha: 0.45),
            );
          }),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tp.textMuted.withValues(alpha: 0.45);
          }
          if (states.contains(WidgetState.selected)) {
            return tp.onBrand;
          }
          return tp.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tp.surfaceSubtle;
          }
          if (states.contains(WidgetState.selected)) {
            return tp.brand;
          }
          return tp.surfaceSubtle;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return scheme.outline;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tp.brand;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(tp.onBrand),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tp.brand;
          return scheme.outline;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tp.brand,
        linearTrackColor: tp.surfacePressed,
        circularTrackColor: tp.surfacePressed,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: tp.brand,
        inactiveTrackColor: tp.surfacePressed,
        thumbColor: tp.brand,
        overlayColor: tp.brandSoft,
        valueIndicatorColor: tp.brand,
        valueIndicatorTextStyle: TextStyle(color: tp.onBrand),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: tp.brand,
        labelColor: tp.brandInk,
        unselectedLabelColor: tp.textMuted,
        dividerColor: Colors.transparent,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tp.brand,
        selectionColor: tp.brand.withValues(alpha: 0.22),
        selectionHandleColor: tp.brand,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: tp.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: tp.brand,
        headerForegroundColor: tp.onBrand,
        rangeSelectionBackgroundColor: scheme.primaryContainer,
        rangePickerBackgroundColor: tp.surface,
        rangePickerHeaderBackgroundColor: tp.brand,
        rangePickerHeaderForegroundColor: tp.onBrand,
        shape: dialogShape,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: tp.surface,
        dialBackgroundColor: tp.surfaceSubtle,
        hourMinuteColor: scheme.primaryContainer,
        hourMinuteTextColor: tp.brandInk,
        dayPeriodColor: scheme.primaryContainer,
        dayPeriodTextColor: tp.brandInk,
        shape: dialogShape,
      ),
      inputDecorationTheme: _usesIosTheme
          ? InputDecorationTheme(
              filled: true,
              fillColor: tp.surface,
              border: iosInputBorder,
              enabledBorder: iosInputBorder,
              focusedBorder: iosFocusedInputBorder,
              errorBorder: iosErrorInputBorder,
              focusedErrorBorder: iosErrorInputBorder,
            )
          : InputDecorationTheme(
              border: inputBorder,
            ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      extensions: <ThemeExtension<dynamic>>[tp],
    );
  }
}
