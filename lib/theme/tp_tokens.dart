import 'package:flutter/painting.dart';

/// Shared visual design tokens for TechPie across all platforms.
///
/// See `docs/DESIGN_SYSTEM.md` for usage rules and platform boundaries.
abstract final class TpTokens {
  // Brand & semantic base palette.
  static const techRedLight = Color(0xFFA30B19);
  static const techRedDark = Color(0xFFE03140);
  static const techRedDarkInk = Color(0xFFFF6470);
  static const iosBlueLight = Color(0xFF007AFF);
  static const iosBlueDark = Color(0xFF0A84FF);
  static const successGreenLight = Color(0xFF15803D);
  static const successGreenDark = Color(0xFF30D158);
  static const successGreen = successGreenDark;
  static const warningAmberLight = Color(0xFFB45309);
  static const warningAmberDark = Color(0xFFF59E0B);
  static const dangerDark = Color(0xFFFF453A);

  // Neutral grouped surfaces.
  static const lightCanvas = Color(0xFFF2F2F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceSubtle = Color(0xFFF2F2F7);
  static const lightSurfacePressed = Color(0xFFE5E5EA);
  static const lightDivider = Color(0x14000000);
  static const lightOutline = Color(0xFFAEAEB2);
  static const lightTextPrimary = Color(0xFF171717);
  static const lightTextSecondary = Color(0xFF3A3A3C);
  static const lightTextMuted = Color(0xFF636366);

  static const darkCanvas = Color(0xFF0A0A0A);
  static const darkSurface = Color(0xFF1C1C1E);
  static const darkSurfaceSubtle = Color(0xFF2C2C2E);
  static const darkSurfacePressed = Color(0xFF3A3A3C);
  static const darkBorder = Color(0x14FFFFFF);
  static const darkOutline = Color(0xFF636366);

  static const amoledCanvas = Color(0xFF000000);
  static const amoledSurface = Color(0xFF141414);
  static const amoledSurfaceSubtle = Color(0xFF1E1E20);
  static const amoledSurfacePressed = Color(0xFF28282B);
  static const amoledBorder = Color(0x1AFFFFFF);

  static const darkTextPrimary = Color(0xFFFAFAFA);
  static const amoledTextPrimary = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0xFFD1D1D6);
  static const darkTextMuted = Color(0xFF98989D);
  static const mutedText = Color(0xFF8E8E93);

  // Spacing (4 dp grid).
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space8 = 48;

  // Border radii (4 standard tiers + bar & pill).
  static const double radiusBar = 2;
  static const double radiusXs = 6;
  static const double radiusS = 10;
  static const double radiusM = 16;
  static const double radiusL = 24;
  static const double radiusPill = 999;

  // Layout geometry.
  static const double pageHorizontalPadding = 16;
  static const double pageHorizontalPaddingWide = 24;
  static const double cardPaddingHorizontal = 16;
  static const double cardPaddingVertical = 14;
  static const double sectionGap = 12;
  static const double singleColumnMaxWidth = 680;
  static const double bentoBreakpoint = 960;

  // Component geometry.
  static const double iconXs = 14;
  static const double iconS = 16;
  static const double iconM = 20;
  static const double iconL = 24;
  static const double featureTileSize = 44;
  static const double accentBarWidth = 3;
  static const double progressBarHeight = 4;

  // Motion durations.
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 240);
  static const Duration durationSlow = Duration(milliseconds: 320);
}
