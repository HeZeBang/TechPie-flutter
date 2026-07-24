import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

const _presenterChannel = MethodChannel('techpie/native_glass_presenter');

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
  try {
    final result = await _presenterChannel.invokeMethod<dynamic>('showAlert', {
      'title': title,
      'message': message,
      'actions': [
        for (final action in actions)
          {
            'label': action.label,
            'isDestructive': action.isDestructive,
            'isDefault': action.isDefault,
          },
      ],
    });

    if (result is! int || result < 0 || result >= actions.length) return null;
    return actions[result].value;
  } on PlatformException {
    if (!fallbackContext.mounted) return null;

    return _showCupertinoAlertDialog<T>(
      context: fallbackContext,
      title: title,
      message: message,
      actions: actions,
    );
  } on MissingPluginException {
    if (!fallbackContext.mounted) return null;

    return _showCupertinoAlertDialog<T>(
      context: fallbackContext,
      title: title,
      message: message,
      actions: actions,
    );
  }
}

Future<T?> _showCupertinoAlertDialog<T>({
  required BuildContext context,
  required String title,
  required String message,
  required List<AdaptiveAlertAction<T>> actions,
}) {
  return showCupertinoDialog<T>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        for (final action in actions)
          CupertinoDialogAction(
            isDefaultAction: action.isDefault,
            isDestructiveAction: action.isDestructive,
            onPressed: () => Navigator.pop(dialogContext, action.value),
            child: Text(action.label),
          ),
      ],
    ),
  );
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
