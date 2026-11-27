import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/platform.dart';
import 'design_system/tp_list_row.dart';

/// Choice item for [showAdaptiveOptionSheet].
@immutable
class AdaptiveOptionItem<T> {
  const AdaptiveOptionItem({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

/// Presents a platform-appropriate option chooser:
/// - iOS: native `CupertinoActionSheet` with checkmark indicator
/// - macOS: compact desktop `Dialog` with `TpListRow` choices
/// - Other platforms: `SimpleDialog`
Future<T?> showAdaptiveOptionSheet<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<AdaptiveOptionItem<T>> options,
  T? selectedValue,
}) {
  if (isIos()) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(title),
        message: message == null || message.isEmpty ? null : Text(message),
        actions: [
          for (final option in options)
            CupertinoActionSheetAction(
              isDefaultAction: option.value == selectedValue,
              onPressed: () => Navigator.pop(sheetContext, option.value),
              child: Text(
                option.value == selectedValue
                    ? '${option.label} ✓'
                    : option.label,
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  if (usesMacOsNativeControls()) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.tpColors;
        return Dialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TpTokens.radiusL),
            side: BorderSide(color: colors.divider),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TpTokens.space5,
                    TpTokens.space4,
                    TpTokens.space5,
                    TpTokens.space3,
                  ),
                  child: Text(
                    title,
                    style: TpTypography.cardTitle(colors),
                  ),
                ),
                Divider(height: 1, color: colors.divider),
                for (var i = 0; i < options.length; i++)
                  TpListRow(
                    title: options[i].label,
                    showDivider: i < options.length - 1 ||
                        (message != null && message.isNotEmpty),
                    trailing: options[i].value == selectedValue
                        ? Icon(
                            TpIcons.check,
                            size: TpTokens.iconS,
                            color: colors.brandInk,
                          )
                        : null,
                    onTap: () => Navigator.pop(dialogContext, options[i].value),
                  ),
                if (message != null && message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TpTokens.space5,
                      TpTokens.space3,
                      TpTokens.space5,
                      TpTokens.space2,
                    ),
                    child: Text(
                      message,
                      style: TpTypography.itemMeta(colors),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TpTokens.space4,
                    TpTokens.space1,
                    TpTokens.space4,
                    TpTokens.space3,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('取消'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.tpColors;
      return SimpleDialog(
        title: Text(title),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option.value),
              child: Row(
                children: [
                  Icon(
                    option.value == selectedValue
                        ? TpIcons.checkCircle
                        : TpIcons.circleDot,
                    size: 20,
                    color: option.value == selectedValue
                        ? colors.brandInk
                        : colors.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Flexible(child: Text(option.label)),
                ],
              ),
            ),
          if (message != null && message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(message),
            ),
        ],
      );
    },
  );
}
