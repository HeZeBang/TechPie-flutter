import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/presentation/theme/colors.dart';
import 'package:techpie/features/campus_card/presentation/theme/theme.dart';
import 'package:techpie/features/campus_card/presentation/theme/tokens.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/theme/tp_colors.dart';

void main() {
  test(
      'Android groups and segmented controls remain distinct with legacy colors',
      () {
    for (final scheme in [
      const ColorScheme.light(),
      const ColorScheme.dark(surface: Color(0xFF1B1B1F)),
    ]) {
      final host =
          ThemeData(platform: TargetPlatform.android, colorScheme: scheme);
      final theme = GeekPayTheme.inherit(host);
      final colors = theme.extension<GpColors>()!;
      final background = colors.bg.computeLuminance();
      final group = colors.surface.computeLuminance();
      final track = colors.surfaceDisabled.computeLuminance();

      expect(colors.bg, host.scaffoldBackgroundColor);
      expect(theme.colorScheme, host.colorScheme);
      if (scheme.brightness == Brightness.light) {
        expect(background - group, greaterThan(0.08));
        expect(group - track, greaterThan(0.05));
      } else {
        expect(group - background, greaterThan(0.01));
        expect(track - group, greaterThan(0.01));
      }
    }
  });

  test('iOS keeps the host surface colors', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    final host = ThemeData(platform: TargetPlatform.iOS, colorScheme: scheme);
    final colors = GeekPayTheme.inherit(host).extension<GpColors>()!;

    expect(colors.bg, host.scaffoldBackgroundColor);
    expect(colors.surface, scheme.surfaceContainerLow);
    expect(colors.surfaceRaised, scheme.surfaceContainer);
    expect(colors.surfaceDisabled, scheme.surfaceContainerHighest);
  });

  test('GeekPayTheme bridges GpColors directly from TpColors when attached',
      () async {
    SharedPreferences.setMockInitialValues({});
    final themeService =
        ThemeService(StorageService(await SharedPreferences.getInstance()));

    for (final mode in [
      AppThemeMode.light,
      AppThemeMode.dark,
      AppThemeMode.amoled,
    ]) {
      await themeService.setMode(mode);
      final host = mode == AppThemeMode.light
          ? themeService.lightTheme
          : themeService.darkTheme;
      final tp = host.extension<TpColors>()!;
      final gp = GeekPayTheme.inherit(host).extension<GpColors>()!;

      expect(gp.bg, tp.canvas);
      expect(gp.surface, tp.surface);
      expect(gp.surfaceRaised, tp.surfaceSubtle);
      expect(gp.surfaceDisabled, tp.surfacePressed);
      expect(gp.action, tp.brand);
      expect(gp.actionAlt, tp.brandSoft);
      expect(gp.accent, tp.brand);
      expect(gp.textPrimary, tp.textPrimary);
      expect(gp.textSecondary, tp.textMuted);
      expect(gp.qrForeground, GpTokens.qrForeground);
      expect(gp.qrBackground, GpTokens.qrBackground);
      expect(gp.cardMat, GpTokens.cardMat);
      expect(gp.textOnCard, GpTokens.textOnCard);
    }
  });
}
