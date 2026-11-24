import 'package:flutter/material.dart';

import 'tp_tokens.dart';

/// Semantic color roles shared across every TechPie surface and platform.
///
/// Neutral roles (`canvas`, `surface`, `surfaceSubtle`, `border`, `text*`) stay
/// strictly neutral regardless of user accent preference. Only `brand`,
/// `brandSoft`, and `onBrand` adapt when the user selects a system accent.
@immutable
final class TpColors extends ThemeExtension<TpColors> {
  const TpColors({
    required this.brightness,
    required this.isAmoled,
    required this.canvas,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfacePressed,
    required this.border,
    required this.divider,
    required this.brand,
    required this.brandInk,
    required this.brandSoft,
    required this.onBrand,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.infoBlue,
    required this.successGreen,
    required this.warningAmber,
    required this.dangerRed,
  });

  factory TpColors.light({Color? accent, Color? onAccent}) {
    final brand = accent ?? TpTokens.techRedLight;
    final resolvedOnBrand = onAccent ?? _contrastForeground(brand);
    return TpColors(
      brightness: Brightness.light,
      isAmoled: false,
      canvas: TpTokens.lightCanvas,
      surface: TpTokens.lightSurface,
      surfaceSubtle: TpTokens.lightSurfaceSubtle,
      surfacePressed: TpTokens.lightSurfacePressed,
      border: Colors.transparent,
      divider: TpTokens.lightDivider,
      brand: brand,
      brandInk: _lightInkFor(brand),
      brandSoft: brand.withValues(alpha: 0.09),
      onBrand: resolvedOnBrand,
      textPrimary: TpTokens.lightTextPrimary,
      textSecondary: TpTokens.lightTextSecondary,
      textMuted: TpTokens.lightTextMuted,
      infoBlue: TpTokens.iosBlueLight,
      successGreen: TpTokens.successGreenLight,
      warningAmber: TpTokens.warningAmberLight,
      dangerRed: TpTokens.techRedLight,
    );
  }

  factory TpColors.dark({
    bool amoled = false,
    Color? accent,
    Color? onAccent,
  }) {
    final brand = accent ?? TpTokens.techRedDark;
    final resolvedOnBrand = onAccent ?? _contrastForeground(brand);
    final brandInk =
        accent == null ? TpTokens.techRedDarkInk : _darkInkFor(accent);
    return TpColors(
      brightness: Brightness.dark,
      isAmoled: amoled,
      canvas: amoled ? TpTokens.amoledCanvas : TpTokens.darkCanvas,
      surface: amoled ? TpTokens.amoledSurface : TpTokens.darkSurface,
      surfaceSubtle:
          amoled ? TpTokens.amoledSurfaceSubtle : TpTokens.darkSurfaceSubtle,
      surfacePressed:
          amoled ? TpTokens.amoledSurfacePressed : TpTokens.darkSurfacePressed,
      border: amoled ? TpTokens.amoledBorder : TpTokens.darkBorder,
      divider: amoled ? TpTokens.amoledBorder : TpTokens.darkBorder,
      brand: brand,
      brandInk: brandInk,
      brandSoft: brand.withValues(alpha: 0.14),
      onBrand: resolvedOnBrand,
      textPrimary:
          amoled ? TpTokens.amoledTextPrimary : TpTokens.darkTextPrimary,
      textSecondary: TpTokens.darkTextSecondary,
      textMuted: TpTokens.darkTextMuted,
      infoBlue: TpTokens.iosBlueDark,
      successGreen: TpTokens.successGreenDark,
      warningAmber: TpTokens.warningAmberDark,
      dangerRed: TpTokens.dangerDark,
    );
  }

  static Color _contrastForeground(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? Colors.white
          : TpTokens.lightTextPrimary;

  /// Ensures foreground brand text/icons stay WCAG-AA legible on light cards.
  static Color _lightInkFor(Color color) {
    if (color.computeLuminance() <= 0.17) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(hsl.lightness.clamp(0.0, 0.38)).toColor();
  }

  /// Ensures foreground brand text/icons stay WCAG-AA legible on dark surfaces.
  static Color _darkInkFor(Color color) {
    if (color.computeLuminance() >= 0.28) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(hsl.lightness.clamp(0.66, 0.78)).toColor();
  }

  static TpColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<TpColors>() ?? fromTheme(theme);
  }

  static TpColors fromTheme(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? TpColors.dark(
            amoled: theme.scaffoldBackgroundColor == Colors.black,
          )
        : TpColors.light();
  }

  final Brightness brightness;
  final bool isAmoled;
  final Color canvas;
  final Color surface;
  final Color surfaceSubtle;
  final Color surfacePressed;
  final Color border;
  final Color divider;
  final Color brand;

  /// High-contrast foreground brand color for text and icons placed on
  /// [surface], [surfaceSubtle], or [brandSoft] (e.g. `#A30B19` in light mode
  /// and `#FF6470` in dark/AMOLED mode).
  final Color brandInk;
  final Color brandSoft;
  final Color onBrand;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color infoBlue;
  final Color successGreen;
  final Color warningAmber;
  final Color dangerRed;

  bool get isDark => brightness == Brightness.dark;

  /// Opaque tinted brand container composited onto [surface], safe for elevated
  /// Material 3 controls (chips, segmented buttons, tonal buttons, pickers).
  Color get opaqueBrandContainer => Color.alphaBlend(
        brand.withValues(alpha: isDark ? 0.22 : 0.11),
        surface,
      );

  /// Opaque tinted error container composited onto [surface].
  Color get opaqueDangerContainer => Color.alphaBlend(
        dangerRed.withValues(alpha: isDark ? 0.22 : 0.12),
        surface,
      );

  /// Opaque tinted success container composited onto [surface].
  Color get opaqueSuccessContainer => Color.alphaBlend(
        successGreen.withValues(alpha: isDark ? 0.22 : 0.12),
        surface,
      );

  /// Builds a Material 3 [ColorScheme] aligned with this neutral surface palette
  /// without inheriting Material 2 purple/teal defaults from `ColorScheme.light`
  /// or `ColorScheme.dark`.
  ColorScheme toColorScheme() {
    final brandContainer = opaqueBrandContainer;
    final secondaryContainerColor = Color.alphaBlend(
      brand.withValues(alpha: isDark ? 0.20 : 0.10),
      surface,
    );
    final successContainer = opaqueSuccessContainer;
    final errorContainerColor = opaqueDangerContainer;
    final inverseSurfaceColor =
        isDark ? TpTokens.lightCanvas : TpTokens.darkSurface;
    final onInverseSurfaceColor =
        isDark ? TpTokens.lightTextPrimary : TpTokens.darkTextPrimary;
    final inversePrimaryColor = isDark
        ? (brand == TpTokens.techRedDark
            ? TpTokens.techRedLight
            : _lightInkFor(brand))
        : (brand == TpTokens.techRedLight
            ? TpTokens.techRedDarkInk
            : _darkInkFor(brand));

    return ColorScheme(
      brightness: brightness,
      primary: brand,
      onPrimary: onBrand,
      primaryContainer: brandContainer,
      onPrimaryContainer: brandInk,
      primaryFixed: brandContainer,
      primaryFixedDim: Color.alphaBlend(
        brand.withValues(alpha: isDark ? 0.30 : 0.16),
        surface,
      ),
      onPrimaryFixed: brandInk,
      onPrimaryFixedVariant: brandInk,
      secondary: brand,
      onSecondary: onBrand,
      secondaryContainer: secondaryContainerColor,
      onSecondaryContainer: brandInk,
      secondaryFixed: secondaryContainerColor,
      secondaryFixedDim: Color.alphaBlend(
        brand.withValues(alpha: isDark ? 0.28 : 0.15),
        surface,
      ),
      onSecondaryFixed: brandInk,
      onSecondaryFixedVariant: brandInk,
      tertiary: successGreen,
      onTertiary: Colors.white,
      tertiaryContainer: successContainer,
      onTertiaryContainer: successGreen,
      tertiaryFixed: successContainer,
      tertiaryFixedDim: Color.alphaBlend(
        successGreen.withValues(alpha: isDark ? 0.30 : 0.18),
        surface,
      ),
      onTertiaryFixed: successGreen,
      onTertiaryFixedVariant: successGreen,
      error: dangerRed,
      onError: Colors.white,
      errorContainer: errorContainerColor,
      onErrorContainer: dangerRed,
      surface: canvas,
      onSurface: textPrimary,
      surfaceDim: canvas,
      surfaceBright: surface,
      surfaceContainerLowest: isDark ? canvas : surface,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceSubtle,
      surfaceContainerHighest: surfacePressed,
      onSurfaceVariant: textMuted,
      outline: isDark ? TpTokens.darkOutline : TpTokens.lightOutline,
      outlineVariant: divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: inverseSurfaceColor,
      onInverseSurface: onInverseSurfaceColor,
      inversePrimary: inversePrimaryColor,
      surfaceTint: Colors.transparent,
    );
  }

  @override
  TpColors copyWith({
    Brightness? brightness,
    bool? isAmoled,
    Color? canvas,
    Color? surface,
    Color? surfaceSubtle,
    Color? surfacePressed,
    Color? border,
    Color? divider,
    Color? brand,
    Color? brandInk,
    Color? brandSoft,
    Color? onBrand,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? infoBlue,
    Color? successGreen,
    Color? warningAmber,
    Color? dangerRed,
  }) {
    return TpColors(
      brightness: brightness ?? this.brightness,
      isAmoled: isAmoled ?? this.isAmoled,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      brand: brand ?? this.brand,
      brandInk: brandInk ?? this.brandInk,
      brandSoft: brandSoft ?? this.brandSoft,
      onBrand: onBrand ?? this.onBrand,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      infoBlue: infoBlue ?? this.infoBlue,
      successGreen: successGreen ?? this.successGreen,
      warningAmber: warningAmber ?? this.warningAmber,
      dangerRed: dangerRed ?? this.dangerRed,
    );
  }

  @override
  TpColors lerp(ThemeExtension<TpColors>? other, double t) {
    if (other is! TpColors) return this;
    return TpColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      isAmoled: t < 0.5 ? isAmoled : other.isAmoled,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceSubtle:
          Color.lerp(surfaceSubtle, other.surfaceSubtle, t) ?? surfaceSubtle,
      surfacePressed:
          Color.lerp(surfacePressed, other.surfacePressed, t) ?? surfacePressed,
      border: Color.lerp(border, other.border, t) ?? border,
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      brand: Color.lerp(brand, other.brand, t) ?? brand,
      brandInk: Color.lerp(brandInk, other.brandInk, t) ?? brandInk,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t) ?? brandSoft,
      onBrand: Color.lerp(onBrand, other.onBrand, t) ?? onBrand,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      infoBlue: Color.lerp(infoBlue, other.infoBlue, t) ?? infoBlue,
      successGreen:
          Color.lerp(successGreen, other.successGreen, t) ?? successGreen,
      warningAmber:
          Color.lerp(warningAmber, other.warningAmber, t) ?? warningAmber,
      dangerRed: Color.lerp(dangerRed, other.dangerRed, t) ?? dangerRed,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TpColors &&
        other.brightness == brightness &&
        other.isAmoled == isAmoled &&
        other.canvas == canvas &&
        other.surface == surface &&
        other.surfaceSubtle == surfaceSubtle &&
        other.surfacePressed == surfacePressed &&
        other.border == border &&
        other.divider == divider &&
        other.brand == brand &&
        other.brandInk == brandInk &&
        other.brandSoft == brandSoft &&
        other.onBrand == onBrand &&
        other.textPrimary == textPrimary &&
        other.textSecondary == textSecondary &&
        other.textMuted == textMuted &&
        other.infoBlue == infoBlue &&
        other.successGreen == successGreen &&
        other.warningAmber == warningAmber &&
        other.dangerRed == dangerRed;
  }

  @override
  int get hashCode => Object.hashAll([
        brightness,
        isAmoled,
        canvas,
        surface,
        surfaceSubtle,
        surfacePressed,
        border,
        divider,
        brand,
        brandInk,
        brandSoft,
        onBrand,
        textPrimary,
        textSecondary,
        textMuted,
        infoBlue,
        successGreen,
        warningAmber,
        dangerRed,
      ]);
}

extension TpColorsContext on BuildContext {
  TpColors get tpColors => TpColors.of(this);
}
