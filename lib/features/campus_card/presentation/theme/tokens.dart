import 'package:flutter/painting.dart';

/// Semantic design tokens per DESIGN_SYSTEM Part A (locked values).
abstract final class GpTokens {
  // Fixed palettes (theme-independent).
  static const qrForeground = Color(0xFF000000);
  static const qrBackground = Color(0xFFFFFFFF);
  static const cardMat = Color(0xFFFFFFFF);
  static const textOnCard = Color(0xFFFFFFFF);
  static const cardCanvas = Color(0xFFFEF9F9);
  static const campusRed = Color(0xFF9D0A12);
  static const appleBlue = Color(0xFF007AFF);
  static const appleGreen = Color(0xFF30D158);
  static const groupedFillLight = Color(0xFFFFFFFF);
  static const groupedFillDark = Color(0xFF1C1C1E);

  // Glass (navigation & control layers only).
  static const glassOpacity = 0.72;
  static const glassBlurSigma = 24.0;
  static const glassTintLight = Color(0x14FFFFFF);
  static const glassTintDark = Color(0x0FFFFFFF);
  static const glassHighlightOpacity = 0.14;
  static const glassBorderOpacity = 0.09;
  static const glassFallbackHighlightOpacity = 0.06;
  static const glassFallbackLight = Color(0xFFFAFBFC);
  static const glassScrimBehindNav = Color(0x0A000000);

  // Spacing (4dp base grid).
  static const space0 = 0.0;
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;
  static const space8 = 48.0;

  static const widthMax = 600.0;
  static const minTouchTarget = 48.0;

  // Radii.
  static const radius0 = 0.0;
  static const radiusS = 8.0;
  static const radiusM = 12.0;
  static const radiusL = 16.0;
  static const radiusXl = 24.0;
  static const radiusFull = 999.0;

  // Elevation shadows (Part A §5). Elevation is not constrained to the grid.
  static List<BoxShadow> elevation1(bool dark) => [
        BoxShadow(
          offset: const Offset(0, 1),
          blurRadius: 4,
          color: const Color(0xFF000000).withValues(alpha: 0.08),
        ),
      ];

  static List<BoxShadow> elevation2(bool dark) => [
        BoxShadow(
          offset: const Offset(0, 4),
          blurRadius: 16,
          color: const Color(0xFF000000).withValues(alpha: dark ? 0.22 : 0.10),
        ),
      ];

  static List<BoxShadow> elevation3(bool dark) => [
        BoxShadow(
          offset: const Offset(0, 10),
          blurRadius: 32,
          color: const Color(0xFF000000).withValues(alpha: dark ? 0.30 : 0.14),
        ),
      ];

  // Motion contract (PRODUCT_SPEC §4).
  static const scanModalDuration = Duration(milliseconds: 300);
  static const standardSegDuration = Duration(milliseconds: 300);
  static const resultOverlayDuration = Duration(milliseconds: 320);
  static const qrCrossfadeDuration = Duration(milliseconds: 200);
  static const balanceBlendDuration = Duration(milliseconds: 300);
  static const balanceBlendReducedDuration = Duration(milliseconds: 180);
  static const pollingPulseDuration = Duration(milliseconds: 1600);
}
