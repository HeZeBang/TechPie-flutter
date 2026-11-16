import 'package:flutter/foundation.dart';

/// The kind of small surface the app is currently rendered on.
enum GlanceSurface { none, cover, rear }

/// Native description of the screen this activity is attached to.
@immutable
final class ScreenFormFactorInfo {
  const ScreenFormFactorInfo({
    required this.isFlipDevice,
    required this.isRearDevice,
    required this.displayId,
    required this.windowWidthPx,
    required this.windowHeightPx,
    required this.density,
    required this.densityDpi,
    required this.isDefaultDisplay,
    required this.isInMultiWindowMode,
    required this.model,
    required this.manufacturer,
    required this.sdkInt,
  });

  factory ScreenFormFactorInfo.fromMap(Map<Object?, Object?> map) {
    bool flag(String key) => map[key] == true;
    int integer(String key) {
      final value = map[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    double number(String key) {
      final value = map[key];
      final parsed = value is num
          ? value.toDouble()
          : value is String
              ? double.tryParse(value)
              : null;
      return parsed != null && parsed > 0 ? parsed : 1;
    }

    String text(String key) => map[key]?.toString() ?? '';

    return ScreenFormFactorInfo(
      isFlipDevice: flag('isFlipDevice'),
      isRearDevice: flag('isRearDevice'),
      displayId: integer('displayId'),
      windowWidthPx: integer('windowWidthPx'),
      windowHeightPx: integer('windowHeightPx'),
      density: number('density'),
      densityDpi: integer('densityDpi'),
      isDefaultDisplay: flag('isDefaultDisplay'),
      isInMultiWindowMode: flag('isInMultiWindowMode'),
      model: text('model'),
      manufacturer: text('manufacturer'),
      sdkInt: integer('sdkInt'),
    );
  }

  final bool isFlipDevice;
  final bool isRearDevice;
  final int displayId;
  final int windowWidthPx;
  final int windowHeightPx;
  final double density;
  final int densityDpi;
  final bool isDefaultDisplay;
  final bool isInMultiWindowMode;
  final String model;
  final String manufacturer;
  final int sdkInt;

  double get windowWidthDp => windowWidthPx / density;

  double get windowHeightDp => windowHeightPx / density;

  @override
  bool operator ==(Object other) =>
      other is ScreenFormFactorInfo &&
      other.isFlipDevice == isFlipDevice &&
      other.isRearDevice == isRearDevice &&
      other.displayId == displayId &&
      other.windowWidthPx == windowWidthPx &&
      other.windowHeightPx == windowHeightPx &&
      other.density == density &&
      other.densityDpi == densityDpi &&
      other.isDefaultDisplay == isDefaultDisplay &&
      other.isInMultiWindowMode == isInMultiWindowMode &&
      other.model == model &&
      other.manufacturer == manufacturer &&
      other.sdkInt == sdkInt;

  @override
  int get hashCode => Object.hash(
        isFlipDevice,
        isRearDevice,
        displayId,
        windowWidthPx,
        windowHeightPx,
        density,
        densityDpi,
        isDefaultDisplay,
        isInMultiWindowMode,
        model,
        manufacturer,
        sdkInt,
      );

  @override
  String toString() =>
      'ScreenFormFactorInfo(flip: $isFlipDevice, rear: $isRearDevice, '
      'display: $displayId, ${windowWidthPx}x$windowHeightPx @${density}x, '
      'multiWindow: $isInMultiWindowMode, $manufacturer $model)';
}
