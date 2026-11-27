import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../utils/platform.dart';
import 'macos/macos_native_controls.dart';

/// Entry in [showAdaptiveContextMenu].
@immutable
class AdaptiveContextMenuItem<T> {
  const AdaptiveContextMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.sfSymbol,
    this.enabled = true,
    this.checked = false,
    this.destructive = false,
  }) : isDivider = false;

  const AdaptiveContextMenuItem.divider()
      : value = null,
        label = '',
        icon = null,
        sfSymbol = null,
        enabled = false,
        checked = false,
        destructive = false,
        isDivider = true;

  final T? value;
  final String label;
  final IconData? icon;
  final String? sfSymbol;
  final bool enabled;
  final bool checked;
  final bool destructive;
  final bool isDivider;
}

/// Presents a native `NSMenu` popup on macOS (falling back to Flutter `showMenu`
/// in unit tests where the platform channel is absent), and a styled Material
/// popup menu on other desktop/non-macOS platforms.
Future<T?> showAdaptiveContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<AdaptiveContextMenuItem<T>> items,
}) {
  if (usesMacOsNativeUiModals()) {
    return _showMacOsContextMenu<T>(
      context: context,
      globalPosition: globalPosition,
      items: items,
    );
  }
  return _showFlutterContextMenu<T>(
    context: context,
    globalPosition: globalPosition,
    items: items,
  );
}

Future<T?> _showMacOsContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<AdaptiveContextMenuItem<T>> items,
}) async {
  try {
    final index = await MacosNativeUi.showContextMenu(
      globalPosition: globalPosition,
      isDark: context.tpColors.isDark,
      items: [
        for (final item in items)
          item.isDivider
              ? const MacosPopUpItem.divider()
              : MacosPopUpItem(
                  label: item.label,
                  sfSymbol: item.sfSymbol,
                  enabled: item.enabled,
                  checked: item.checked,
                  isDestructive: item.destructive,
                ),
      ],
    );
    if (index == null || index < 0 || index >= items.length) return null;
    final picked = items[index];
    return picked.isDivider ? null : picked.value;
  } on MissingPluginException {
    if (!context.mounted) return null;
    return _showFlutterContextMenu<T>(
      context: context,
      globalPosition: globalPosition,
      items: items,
    );
  }
}

Future<T?> _showFlutterContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<AdaptiveContextMenuItem<T>> items,
}) {
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
  if (overlay is! RenderBox) return Future<T?>.value(null);
  final colors = context.tpColors;

  return showMenu<T>(
    context: context,
    color: colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TpTokens.radiusM),
      side: BorderSide(color: colors.divider),
    ),
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    ),
    items: [
      for (final item in items)
        if (item.isDivider)
          const PopupMenuDivider()
        else
          PopupMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.checked) ...[
                  Icon(TpIcons.check, size: TpTokens.iconS, color: colors.brandInk),
                  const SizedBox(width: TpTokens.space2),
                ] else if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: TpTokens.iconS,
                    color: item.destructive
                        ? colors.dangerRed
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: TpTokens.space2),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    style: TpTypography.itemTitle(colors).copyWith(
                      color: item.destructive
                          ? colors.dangerRed
                          : item.enabled
                              ? colors.textPrimary
                              : colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
    ],
  );
}
