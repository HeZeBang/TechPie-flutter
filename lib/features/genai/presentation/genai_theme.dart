import 'package:flutter/material.dart';

/// Chat-specific spacing and controls, inheriting the user's app palette.
ThemeData genAiTheme(ThemeData base) {
  final scheme = base.colorScheme;
  final surface = base.scaffoldBackgroundColor;
  final panel = scheme.surfaceContainerLow;
  final ink = scheme.onSurface;
  final muted = scheme.onSurfaceVariant;
  final border = scheme.outlineVariant;
  final accent = scheme.primary;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    dividerColor: border,
    tooltipTheme: base.tooltipTheme.copyWith(
      waitDuration: const Duration(milliseconds: 700),
      showDuration: const Duration(seconds: 2),
    ),
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    iconTheme: base.iconTheme.copyWith(color: muted, size: 20),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: surface,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: ink,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: shape,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: .16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: muted),
    ),
  );
}
