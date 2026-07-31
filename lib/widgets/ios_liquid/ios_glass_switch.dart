import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/platform.dart';

class IosGlassSwitch extends StatelessWidget {
  const IosGlassSwitch({
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

    return SizedBox(
      width: 52,
      height: iosMinimumInteractiveDimension,
      child: Center(
        child: CupertinoSwitch(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}
