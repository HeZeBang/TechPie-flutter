import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/platform.dart';
import 'macos/macos_native_controls.dart';

/// Menu entry for [AdaptivePopupMenuButton].
@immutable
class AdaptivePopupMenuItem<T> {
  const AdaptivePopupMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.sfSymbol,
    this.checked,
    this.enabled = true,
    this.destructive = false,
  }) : isDivider = false;

  const AdaptivePopupMenuItem.divider()
      : value = null,
        label = '',
        icon = null,
        sfSymbol = null,
        checked = null,
        enabled = false,
        destructive = false,
        isDivider = true;

  final T? value;
  final String label;
  final IconData? icon;
  final String? sfSymbol;
  final bool? checked;
  final bool enabled;
  final bool destructive;
  final bool isDivider;
}

/// Platform-adaptive toolbar/action menu button:
/// - macOS: native `NSPopUpButton(pullsDown: true)` (`MacosNativePopUpButton.menu`)
/// - iOS: native `UIMenu` (`CNPopupMenuButton.icon` / `CNPopupMenuButton`)
/// - Other platforms: Material `PopupMenuButton`
class AdaptivePopupMenuButton<T> extends StatelessWidget {
  const AdaptivePopupMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = TpIcons.more,
    this.sfSymbol = 'ellipsis',
    this.label,
    this.tooltip,
    this.enabled = true,
  });

  final List<AdaptivePopupMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final String sfSymbol;
  final String? label;
  final String? tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (usesMacOsNativeControls()) {
      return MacosNativePopUpButton.menu(
        buttonTitle: label,
        buttonIconName: (label == null || label!.isEmpty) ? sfSymbol : null,
        semanticLabel: tooltip ?? label,
        enabled: enabled,
        borderless: label == null || label!.isEmpty,
        items: [
          for (final item in items)
            item.isDivider
                ? const MacosPopUpItem.divider()
                : MacosPopUpItem(
                    label: item.label,
                    sfSymbol: item.sfSymbol,
                    checked: item.checked ?? false,
                    enabled: item.enabled,
                    isDestructive: item.destructive,
                  ),
        ],
        onSelected: (index) {
          if (index >= 0 && index < items.length) {
            final value = items[index].value;
            if (value != null) onSelected(value);
          }
        },
      );
    }

    if (isIos()) {
      final tint = Theme.of(context).colorScheme.primary;
      final cnItems = <CNPopupMenuEntry>[
        for (final item in items)
          item.isDivider
              ? const CNPopupMenuDivider()
              : CNPopupMenuItem(
                  label: item.label,
                  icon: item.sfSymbol == null
                      ? null
                      : CNSymbol(item.sfSymbol!, size: 0),
                  checked: item.checked ?? false,
                  enabled: item.enabled,
                  isDestructive: item.destructive,
                ),
      ];
      void select(int index) {
        if (index >= 0 && index < items.length) {
          final value = items[index].value;
          if (value != null) onSelected(value);
        }
      }

      final button = (label != null && label!.isNotEmpty)
          ? CNPopupMenuButton(
              buttonLabel: label!,
              semanticLabel: tooltip ?? label,
              items: cnItems,
              onSelected: select,
              height: iosMinimumInteractiveDimension,
              shrinkWrap: true,
              buttonStyle: CNButtonStyle.glass,
              tint: tint,
            )
          : CNPopupMenuButton.icon(
              buttonIcon: CNSymbol(sfSymbol, size: 20, color: tint),
              semanticLabel: tooltip,
              items: cnItems,
              onSelected: select,
              tint: tint,
            );

      return IgnorePointer(
        ignoring: !enabled,
        child: Opacity(opacity: enabled ? 1.0 : 0.45, child: button),
      );
    }

    return PopupMenuButton<T>(
      enabled: enabled,
      icon: (label == null || label!.isEmpty) ? Icon(icon) : null,
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final item in items)
          if (item.isDivider)
            const PopupMenuDivider()
          else if (item.checked != null)
            CheckedPopupMenuItem<T>(
              value: item.value as T,
              checked: item.checked!,
              enabled: item.enabled,
              child: Text(item.label),
            )
          else
            PopupMenuItem<T>(
              value: item.value as T,
              enabled: item.enabled,
              child: Row(
                children: [
                  if (item.icon != null) ...[
                    Icon(item.icon, size: TpTokens.iconM),
                    const SizedBox(width: TpTokens.space3),
                  ],
                  Flexible(child: Text(item.label)),
                ],
              ),
            ),
      ],
      child: (label != null && label!.isNotEmpty)
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: TpTokens.iconS),
                  const SizedBox(width: 6),
                  Text(label!),
                ],
              ),
            )
          : null,
    );
  }
}
