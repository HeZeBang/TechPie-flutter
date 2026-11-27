import 'package:flutter/material.dart';

import 'design_system/tp_segmented_control.dart';

class AdaptiveSegmentedControl extends StatelessWidget {
  const AdaptiveSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.enabled = true,
    this.shrinkWrap = false,
    this.height,
    this.semanticLabel,
  });

  final int value;
  final List<String> segments;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final bool shrinkWrap;
  final double? height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    return TpSegmentedControl(
      value: value,
      segments: segments,
      onChanged: onChanged,
      enabled: enabled,
      shrinkWrap: shrinkWrap,
      height: height,
      semanticLabel: semanticLabel,
    );
  }
}
