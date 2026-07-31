import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/platform.dart';

class IosNativeSegmentedControl extends StatelessWidget {
  const IosNativeSegmentedControl({
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

    return SizedBox(
      height: iosMinimumInteractiveDimension,
      width: double.infinity,
      child: Center(
        child: SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<int>(
            groupValue: value,
            children: {
              for (var index = 0; index < segments.length; index++)
                index: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    segments[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            },
            onValueChanged: (selection) {
              if (selection != null) onChanged(selection);
            },
          ),
        ),
      ),
    );
  }
}
