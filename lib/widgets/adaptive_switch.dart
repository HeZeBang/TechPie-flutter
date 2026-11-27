import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';
import 'design_system/tp_list_row.dart';
import 'ios/ios_native_controls.dart';
import 'macos/macos_native_controls.dart';

class AdaptiveSwitch extends StatelessWidget {
  const AdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (usesMacOsNativeControls()) {
      return MacosNativeSwitch(
        value: value,
        enabled: enabled,
        semanticLabel: semanticLabel,
        onChanged: onChanged,
      );
    }

    if (usesDirectIosUiKitViews()) {
      return IosDirectNativeSwitch(
        value: value,
        enabled: enabled,
        onChanged: onChanged,
        height: iosMinimumInteractiveDimension,
        color: Theme.of(context).colorScheme.primary,
        semanticLabel: semanticLabel,
      );
    }

    if (!isIos()) {
      return Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
      );
    }

    // UISwitch on iOS 26+; CNSwitch falls back to CupertinoSwitch in tests.
    // It sizes its own platform view from the height, so it is not boxed.
    return CNSwitch(
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      height: iosMinimumInteractiveDimension,
      color: Theme.of(context).colorScheme.primary,
      semanticLabel: semanticLabel,
    );
  }
}

/// Unified switch list row replacing Material `SwitchListTile` across Apple
/// and desktop/Android targets.
class AdaptiveSwitchRow extends StatelessWidget {
  const AdaptiveSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.enabled = true,
    this.showDivider = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = enabled && onChanged != null;
    return TpListRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      showDivider: showDivider,
      trailing: AdaptiveSwitch(
        value: value,
        enabled: effectiveEnabled,
        semanticLabel: title,
        onChanged: (next) => onChanged?.call(next),
      ),
      onTap: effectiveEnabled ? () => onChanged?.call(!value) : null,
    );
  }
}
