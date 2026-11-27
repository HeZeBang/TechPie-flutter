import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';
import 'ios/ios_native_controls.dart';
import 'macos/macos_native_controls.dart';

/// Platform-adaptive continuous/stepped slider:
/// - macOS: native AppKit `NSSlider` (`MacosNativeSlider`)
/// - iOS: native `UISlider` (`IosDirectNativeSlider` / `CNSlider`)
/// - Other platforms: Material `Slider`
class AdaptiveSlider extends StatelessWidget {
  const AdaptiveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.enabled = true,
    this.semanticLabel,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final String? semanticLabel;

  double? get _step =>
      divisions != null && divisions! > 0 && max > min
          ? (max - min) / divisions!
          : null;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && onChanged != null;
    final clamped = value.clamp(min, max).toDouble();

    if (usesMacOsNativeControls()) {
      return MacosNativeSlider(
        value: clamped,
        min: min,
        max: max,
        step: _step,
        enabled: interactive,
        semanticLabel: semanticLabel,
        onChanged: (next) => onChanged?.call(next),
      );
    }

    if (usesDirectIosUiKitViews()) {
      return IosDirectNativeSlider(
        value: clamped,
        min: min,
        max: max,
        step: _step,
        enabled: interactive,
        height: iosMinimumInteractiveDimension,
        color: Theme.of(context).colorScheme.primary,
        semanticLabel: semanticLabel,
        onChanged: (next) => onChanged?.call(next),
      );
    }

    if (isIos()) {
      return CNSlider(
        value: clamped,
        min: min,
        max: max,
        step: _step,
        enabled: interactive,
        height: iosMinimumInteractiveDimension,
        color: Theme.of(context).colorScheme.primary,
        semanticLabel: semanticLabel,
        onChanged: (next) => onChanged?.call(next),
      );
    }

    return Slider(
      value: clamped,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: interactive ? onChanged : null,
    );
  }
}
