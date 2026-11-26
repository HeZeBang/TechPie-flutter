import 'package:flutter/painting.dart';

import 'tp_colors.dart';

/// Shared typographic scale and font fallback definitions for TechPie.
abstract final class TpTypography {
  /// Keep Flutter's platform default as the primary font. Missing glyphs fall
  /// back to installed CJK fonts; unavailable families are skipped by the engine.
  static const List<String> fontFamilyFallback = [
    'PingFang SC',
    'PingFang TC',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Microsoft JhengHei UI',
    'Microsoft JhengHei',
    'Noto Sans CJK SC',
    'Noto Sans CJK TC',
    'Noto Sans SC',
    'Noto Sans TC',
    'WenQuanYi Micro Hei',
    'Arial Unicode MS',
  ];

  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  static TextStyle pageTitle(TpColors colors) => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.4,
        color: colors.textPrimary,
        fontFamilyFallback: fontFamilyFallback,
      );

  static TextStyle pageSubtitle(TpColors colors) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: colors.textMuted,
        fontFamilyFallback: fontFamilyFallback,
      );

  static TextStyle cardTitle(TpColors colors) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: colors.textPrimary,
        fontFamilyFallback: fontFamilyFallback,
      );

  static TextStyle cardMeta(TpColors colors) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: colors.textMuted,
        fontFeatures: tabularFigures,
        fontFamilyFallback: fontFamilyFallback,
      );

  static TextStyle itemTitle(TpColors colors) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: colors.textPrimary,
        fontFamilyFallback: fontFamilyFallback,
      );

  static TextStyle itemMeta(TpColors colors) => TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: colors.textMuted,
        fontFeatures: tabularFigures,
        fontFamilyFallback: fontFamilyFallback,
      );

  static TextStyle featureLabel(TpColors colors) => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        height: 1.25,
        color: colors.textSecondary,
        fontFamilyFallback: fontFamilyFallback,
      );

  static TextStyle badge(Color color) => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        height: 1.15,
        color: color,
        fontFeatures: tabularFigures,
        fontFamilyFallback: fontFamilyFallback,
      );

  static TextStyle numericDisplay(TpColors colors) => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.3,
        color: colors.textPrimary,
        fontFeatures: tabularFigures,
        fontFamilyFallback: fontFamilyFallback,
      );
}
