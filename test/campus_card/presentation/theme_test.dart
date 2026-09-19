import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/presentation/theme/colors.dart';
import 'package:techpie/features/campus_card/presentation/theme/theme.dart';

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
}
