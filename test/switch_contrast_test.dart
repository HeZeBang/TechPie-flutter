import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/widgets/adaptive_switch.dart';

void main() {
  for (final mode in [AppThemeMode.light, AppThemeMode.dark, AppThemeMode.amoled]) {
    testWidgets('enabled off thumb contrasts with the track in ${mode.name} mode', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = ThemeService(StorageService(await SharedPreferences.getInstance()));
      await service.setMode(mode);
      final theme = mode == AppThemeMode.light ? service.lightTheme : service.darkTheme;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: Material(
                color: theme.cardColor,
                child: AdaptiveSwitch(value: false, onChanged: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ratio = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        // Sample the center of the left thumb and the empty right side of the track.
        double luminanceAt(double fraction) {
          final offset = 4 * ((image.height ~/ 2) * image.width + (image.width * fraction).floor());
          return Color.fromARGB(
            255,
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          ).computeLuminance();
        }

        final thumb = luminanceAt(0.32);
        final track = luminanceAt(0.68);
        image.dispose();
        return (math.max(thumb, track) + 0.05) / (math.min(thumb, track) + 0.05);
      });
      expect(ratio, greaterThanOrEqualTo(3));
    });
  }
}
