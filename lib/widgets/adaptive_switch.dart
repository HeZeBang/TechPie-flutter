import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';

class AdaptiveSwitch extends StatelessWidget {
  const AdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) {
      return Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
      );
    }

    // UISwitch on iOS 26+; CNSwitch falls back to CupertinoSwitch before that.
    // It sizes its own platform view from the height, so it is not boxed.
    return CNSwitch(
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      height: iosMinimumInteractiveDimension,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}
