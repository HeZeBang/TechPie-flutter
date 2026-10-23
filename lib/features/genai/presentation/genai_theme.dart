import 'package:flutter/material.dart';

/// A quiet, shared palette scoped to GenAI; preserves the app's fonts and mode.
ThemeData genAiTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final surface = dark ? const Color(0xff181b1b) : Colors.white;
  final panel = dark ? const Color(0xff222626) : const Color(0xfff5f6f6);
  final ink = dark ? const Color(0xffedf0ef) : const Color(0xff202725);
  final muted = dark ? const Color(0xffa6b0ac) : const Color(0xff69736f);
  final border = dark ? const Color(0xff363e3a) : const Color(0xffe5e9e7);
  final accent = dark ? const Color(0xff83d5b6) : const Color(0xff23745a);
  final scheme = base.colorScheme.copyWith(
    primary: accent,
    onPrimary: dark ? const Color(0xff10271d) : Colors.white,
    secondary: accent,
    surface: surface,
    surfaceContainerLowest: surface,
    surfaceContainerLow: panel,
    surfaceContainer: panel,
    surfaceContainerHigh: panel,
    surfaceContainerHighest: panel,
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: muted,
    outlineVariant: border,
    surfaceTint: Colors.transparent,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    dividerColor: border,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    iconTheme: IconThemeData(color: muted, size: 20),
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
