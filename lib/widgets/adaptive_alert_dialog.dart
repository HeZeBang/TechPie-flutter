import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

class AdaptiveAlertAction<T> {
  const AdaptiveAlertAction({
    required this.label,
    this.value,
    this.isDestructive = false,
    this.isDefault = false,
  });

  final String label;
  final T? value;
  final bool isDestructive;
  final bool isDefault;
}

Future<T?> showAdaptiveAlertDialog<T>({
  required BuildContext context,
  required String title,
  required String message,
  required List<AdaptiveAlertAction<T>> actions,
  bool centerContent = false,
}) {
  final usesIosDialog = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  final normalizedActions = _normalizeActions(actions);

  if (usesIosDialog) {
    return _showNativeIosAlert<T>(
      title: title,
      message: message,
      actions: normalizedActions,
      fallbackContext: context,
    );
  }

  return _showFlutterAlertDialog<T>(
    context: context,
    title: title,
    message: message,
    actions: normalizedActions,
    centerContent: centerContent,
  );
}

List<AdaptiveAlertAction<T>> _normalizeActions<T>(
  List<AdaptiveAlertAction<T>> actions,
) {
  final normalized = [
    for (final action in actions)
      if (action.label.trim().isNotEmpty)
        AdaptiveAlertAction<T>(
          label: action.label.trim(),
          value: action.value,
          isDestructive: action.isDestructive,
          isDefault: action.isDefault,
        ),
  ];

  if (normalized.isNotEmpty) return normalized;

  return [AdaptiveAlertAction<T>(label: 'OK', isDefault: true)];
}

Future<T?> _showNativeIosAlert<T>({
  required String title,
  required String message,
  required List<AdaptiveAlertAction<T>> actions,
  required BuildContext fallbackContext,
}) async {
  final result = await CNAlert.show<T>(
    context: fallbackContext,
    title: title,
    message: message,
    actions: [
      for (var i = 0; i < actions.length; i++)
        CNAlertAction<T>(
          label: actions[i].label,
          value: actions[i].value,
          isDestructive: actions[i].isDestructive,
          isDefault: actions[i].isDefault && !actions.take(i).any((action) => action.isDefault),
        ),
    ],
  );
  return result?.value;
}

Future<T?> _showFlutterAlertDialog<T>({
  required BuildContext context,
  required String title,
  required String message,
  required List<AdaptiveAlertAction<T>> actions,
  required bool centerContent,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.tpColors;
      final alignment = centerContent ? TextAlign.center : null;
      final buttons = [
        for (final action in actions)
          action.isDefault && !action.isDestructive
              ? FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, action.value),
                  child: Text(action.label, textAlign: alignment),
                )
              : TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: action.isDestructive
                        ? colors.dangerRed
                        : colors.textSecondary,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, action.value),
                  child: Text(action.label, textAlign: alignment),
                ),
      ];
      return AlertDialog(
        // A release changelog can be longer than a dialog is tall; without this
        // the content is clipped rather than scrolled.
        scrollable: true,
        title: Text(title, textAlign: alignment),
        content: message.trim().isEmpty ? null : Text(message, textAlign: alignment),
        actionsAlignment: centerContent ? MainAxisAlignment.center : null,
        actions: centerContent && buttons.length == 2
            ? [
                Table(
                  defaultColumnWidth: const FlexColumnWidth(),
                  columnWidths: const {1: FixedColumnWidth(TpTokens.space2)},
                  defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
                  children: [
                    TableRow(children: [buttons.first, const SizedBox.shrink(), buttons.last]),
                  ],
                ),
              ]
            : buttons,
      );
    },
  );
}
