import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // A release changelog can be longer than a dialog is tall; without this
      // the content is clipped rather than scrolled.
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        for (final action in actions)
          action.isDefault && !action.isDestructive
              ? FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, action.value),
                  child: Text(action.label),
                )
              : TextButton(
                  onPressed: () => Navigator.pop(dialogContext, action.value),
                  child: Text(
                    action.label,
                    style: action.isDestructive
                        ? TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          )
                        : null,
                  ),
                ),
      ],
    ),
  );
}
