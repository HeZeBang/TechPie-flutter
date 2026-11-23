import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';

class AdaptiveSegmentedControl extends StatelessWidget {
  const AdaptiveSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final int value;
  final List<String> segments;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) {
      return SegmentedButton<int>(
        segments: [
          for (var index = 0; index < segments.length; index++)
            ButtonSegment<int>(value: index, label: Text(segments[index])),
        ],
        selected: {value},
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) onChanged(selection.first);
        },
      );
    }

    // UISegmentedControl, stretched to the row like the sliding control it
    // replaces; CNSegmentedControl falls back to Flutter before iOS 26.
    return SizedBox(
      height: iosMinimumInteractiveDimension,
      width: double.infinity,
      child: Center(
        child: CNSegmentedControl(
          labels: segments,
          selectedIndex: value.clamp(0, segments.length - 1),
          onValueChanged: onChanged,
        ),
      ),
    );
  }
}
