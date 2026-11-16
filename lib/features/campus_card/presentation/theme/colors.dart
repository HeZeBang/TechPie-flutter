import 'package:flutter/material.dart';

import 'tokens.dart';

@immutable
final class GpColors extends ThemeExtension<GpColors> {
  const GpColors({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.surfaceDisabled,
    required this.action,
    required this.actionAlt,
    required this.onAction,
    required this.accent,
    required this.border,
    required this.borderStrong,
    required this.success,
    required this.warning,
    required this.danger,
    required this.statusNormal,
    required this.statusAbnormal,
    required this.qrForeground,
    required this.qrBackground,
    required this.cardMat,
    required this.textOnCard,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color surfaceDisabled;
  final Color action;
  final Color actionAlt;
  final Color onAction;
  final Color accent;
  final Color border;
  final Color borderStrong;
  final Color success;
  final Color warning;
  final Color danger;
  final Color statusNormal;
  final Color statusAbnormal;
  final Color qrForeground;
  final Color qrBackground;
  final Color cardMat;
  final Color textOnCard;

  bool get isDark => brightness == Brightness.dark;

  factory GpColors.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // Android dynamic schemes may omit Material 3 container tones, causing
    // every surface role to fall back to the page background.
    final androidSurfaces = theme.platform == TargetPlatform.android
        ? ColorScheme.fromSeed(
            seedColor: scheme.primary,
            brightness: theme.brightness,
          )
        : null;
    return GpColors(
      brightness: theme.brightness,
      bg: theme.scaffoldBackgroundColor,
      surface: androidSurfaces == null
          ? scheme.surfaceContainerLow
          : isDark
              ? androidSurfaces.surfaceContainerHigh
              : androidSurfaces.surfaceContainer,
      surfaceRaised: androidSurfaces == null
          ? scheme.surfaceContainer
          : isDark
              ? androidSurfaces.surfaceContainerHighest
              : androidSurfaces.surfaceContainerHigh,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      textDisabled: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      surfaceDisabled: androidSurfaces?.surfaceContainerHighest ??
          scheme.surfaceContainerHighest,
      action: scheme.primary,
      actionAlt: scheme.primaryContainer,
      onAction: scheme.onPrimary,
      accent: scheme.primary,
      border: scheme.outlineVariant,
      borderStrong: scheme.outline,
      success: scheme.tertiary,
      warning: isDark ? const Color(0xFFFFB74D) : const Color(0xFFB35400),
      danger: scheme.error,
      statusNormal: scheme.tertiary,
      statusAbnormal: scheme.error,
      qrForeground: GpTokens.qrForeground,
      qrBackground: GpTokens.qrBackground,
      cardMat: GpTokens.cardMat,
      textOnCard: GpTokens.textOnCard,
    );
  }

  @override
  GpColors copyWith() => this;

  @override
  GpColors lerp(ThemeExtension<GpColors>? other, double t) =>
      t < 0.5 ? this : (other as GpColors? ?? this);
}

extension GpColorsContext on BuildContext {
  GpColors get gpColors =>
      Theme.of(this).extension<GpColors>() ??
      GpColors.fromTheme(Theme.of(this));
}
