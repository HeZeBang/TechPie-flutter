import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/screen_form_factor.dart';
import 'package:techpie/services/screen_form_factor_service.dart';

ScreenFormFactorInfo _info({
  bool flip = false,
  bool rear = false,
  int displayId = 0,
}) {
  return ScreenFormFactorInfo(
    isFlipDevice: flip,
    isRearDevice: rear,
    displayId: displayId,
    windowWidthPx: 900,
    windowHeightPx: 600,
    density: 2.75,
    densityDpi: 440,
    isDefaultDisplay: displayId == 0,
    isInMultiWindowMode: false,
    model: 'test',
    manufacturer: 'Xiaomi',
    sdkInt: 36,
  );
}

void main() {
  group('ScreenFormFactorInfo.fromMap', () {
    test('parses native values and keeps bad density usable', () {
      final info = ScreenFormFactorInfo.fromMap(const {
        'isFlipDevice': true,
        'isRearDevice': false,
        'displayId': 0,
        'windowWidthPx': 1392,
        'windowHeightPx': 1208,
        'density': 2.75,
        'densityDpi': 440,
        'isDefaultDisplay': true,
        'isInMultiWindowMode': false,
        'model': 'MIX Flip',
        'manufacturer': 'Xiaomi',
        'sdkInt': 36,
      });
      expect(info.isFlipDevice, isTrue);
      expect(info.windowWidthDp, closeTo(506.18, 0.01));
      expect(info.density, 2.75);
    });

    test('defaults a zero density to 1 instead of dividing by zero', () {
      final info = ScreenFormFactorInfo.fromMap(const {'density': 0});
      expect(info.density, 1);
      expect(info.windowWidthDp, 0);
    });
  });

  group('classifyGlanceSurface', () {
    test('rear-capable phone on its main display stays full', () {
      expect(
        classifyGlanceSurface(
          logicalSize: const Size(400, 800),
          info: _info(rear: true),
          enabled: true,
        ),
        GlanceSurface.none,
      );
    });

    test('rear display is detected by display id', () {
      expect(
        classifyGlanceSurface(
          logicalSize: const Size(340, 210),
          info: _info(rear: true, displayId: 1),
          enabled: true,
        ),
        GlanceSurface.rear,
      );
    });

    test('secondary small landscape works without the reflection probe', () {
      expect(
        classifyGlanceSurface(
          logicalSize: const Size(340, 210),
          info: _info(displayId: 1),
          enabled: true,
        ),
        GlanceSurface.rear,
      );
    });

    test('flip cover is the wide near-square 1392x1208 panel', () {
      expect(
        classifyGlanceSurface(
          logicalSize: const Size(506, 439),
          info: _info(flip: true),
          enabled: true,
        ),
        GlanceSurface.cover,
      );
    });

    test('flip inner screen stays full', () {
      expect(
        classifyGlanceSurface(
          logicalSize: const Size(700, 900),
          info: _info(flip: true),
          enabled: true,
        ),
        GlanceSurface.none,
      );
      // The real inner panel, landscape: 2912x1224 px at 440dpi. It must not
      // be mistaken for the wide cover panel.
      expect(
        classifyGlanceSurface(
          logicalSize: const Size(1059, 445),
          info: _info(flip: true),
          enabled: true,
        ),
        GlanceSurface.none,
      );
    });

    test('small split-screen on a normal phone stays full', () {
      expect(
        classifyGlanceSurface(
          logicalSize: const Size(300, 700),
          info: _info(),
          enabled: true,
        ),
        GlanceSurface.none,
      );
    });

    test('disabled setting and missing info both mean none', () {
      expect(
        classifyGlanceSurface(
          logicalSize: const Size(294, 506),
          info: _info(flip: true),
          enabled: false,
        ),
        GlanceSurface.none,
      );
      expect(
        classifyGlanceSurface(
          logicalSize: const Size(294, 506),
          info: null,
          enabled: true,
        ),
        GlanceSurface.none,
      );
    });
  });

  group('ScreenFormFactorService', () {
    test('loads and notifies only when the answer changes', () async {
      var loads = 0;
      final first = _info(flip: true);
      final service = ScreenFormFactorService(
        loader: () async {
          loads++;
          return first;
        },
        androidOverride: true,
      );
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.refresh();
      expect(service.info, first);
      expect(loads, 1);
      expect(notifications, 1);

      await service.refresh();
      expect(loads, 2);
      expect(notifications, 1);

      service.dispose();
    });

    test('retries a missing plugin once and then gives up', () async {
      var loads = 0;
      final service = ScreenFormFactorService(
        loader: () async {
          loads++;
          throw MissingPluginException('not registered');
        },
        androidOverride: true,
      );
      await service.refresh();
      expect(loads, 2);
      expect(service.info, isNull);
      service.dispose();
    });

    test('does not touch the channel off Android', () async {
      var loads = 0;
      final service = ScreenFormFactorService(
        loader: () async {
          loads++;
          return _info();
        },
        androidOverride: false,
      );
      await service.refresh();
      expect(loads, 0);
      expect(service.info, isNull);
      service.dispose();
    });
  });
}
