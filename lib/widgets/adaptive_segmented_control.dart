import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';
import 'ios/ios_native_controls.dart';
import 'macos/macos_native_controls.dart';

class AdaptiveSegmentedControl extends StatelessWidget {
  const AdaptiveSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.enabled = true,
    this.shrinkWrap = false,
    this.height = 36.0,
    this.semanticLabel,
  });

  final int value;
  final List<String> segments;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final bool shrinkWrap;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    if (usesMacOsNativeControls()) {
      return MacosNativeSegmentedControl(
        labels: segments,
        selectedIndex: value.clamp(0, segments.length - 1),
        onValueChanged: onChanged,
        enabled: enabled,
        shrinkWrap: shrinkWrap,
        height: height,
        semanticLabel: semanticLabel,
      );
    }

    if (usesDirectIosUiKitViews()) {
      return IosDirectNativeSegmentedControl(
        labels: segments,
        selectedIndex: value.clamp(0, segments.length - 1),
        onValueChanged: onChanged,
        enabled: enabled,
        shrinkWrap: shrinkWrap,
        height: height < iosMinimumInteractiveDimension
            ? height
            : iosMinimumInteractiveDimension,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    if (!isIos()) {
      final button = SegmentedButton<int>(
        segments: [
          for (var index = 0; index < segments.length; index++)
            ButtonSegment<int>(
              value: index,
              enabled: enabled,
              label: Text(segments[index], overflow: TextOverflow.ellipsis),
            ),
        ],
        selected: {value.clamp(0, segments.length - 1)},
        onSelectionChanged: enabled
            ? (selection) {
                if (selection.isNotEmpty) onChanged(selection.first);
              }
            : null,
      );
      return shrinkWrap ? Center(child: button) : button;
    }

    // UISegmentedControl, stretched to the row like the sliding control it
    // replaces; CNSegmentedControl falls back to Flutter in unit tests.
    return SizedBox(
      height: iosMinimumInteractiveDimension,
      width: double.infinity,
      child: Center(
        child: CNSegmentedControl(
          labels: segments,
          selectedIndex: value.clamp(0, segments.length - 1),
          enabled: enabled,
          shrinkWrap: shrinkWrap,
          onValueChanged: onChanged,
        ),
      ),
    );
  }
}
