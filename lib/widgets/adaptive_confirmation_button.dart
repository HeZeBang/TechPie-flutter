import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:techpie/utils/platform.dart';

import 'adaptive_alert_dialog.dart';
import 'cupertino_symbol_icons.dart';

class AdaptiveConfirmationButton extends StatelessWidget {
  const AdaptiveConfirmationButton({
    super.key,
    this.label,
    required this.confirmTitle,
    required this.confirmLabel,
    required this.onConfirmed,
    this.icon = Icons.link_off,
    this.sfSymbol = 'link.badge.minus',
    this.destructive = false,
    this.width,
    this.height = iosMinimumInteractiveDimension,
  });

  final String? label;
  final String confirmTitle;
  final String confirmLabel;
  final VoidCallback onConfirmed;
  final IconData icon;
  final String sfSymbol;
  final bool destructive;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hasLabel = label != null && label!.isNotEmpty;
    final buttonWidth =
        width ?? (hasLabel ? 92 : iosMinimumInteractiveDimension);
    final constrainedWidth = buttonWidth < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : buttonWidth;
    final constrainedHeight = height < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : height;
    void callback() => unawaited(_confirm(context));

    if (!isIos()) {
      return SizedBox(
        width: width,
        height: constrainedHeight,
        child: hasLabel
            ? TextButton.icon(
                onPressed: callback,
                icon: Icon(icon, size: 18),
                label: Text(label!),
              )
            : IconButton(
                onPressed: callback,
                icon: Icon(icon, size: 18),
                tooltip: confirmTitle,
              ),
      );
    }

    final color = destructive
        ? CupertinoColors.systemRed
        : CupertinoTheme.of(context).primaryColor;
    return SizedBox(
      width: constrainedWidth,
      height: constrainedHeight,
      child: CupertinoButton(
        // Retain Flutter 3.27 compatibility; minimumSize was added later.
        // ignore: deprecated_member_use
        minSize: iosMinimumInteractiveDimension,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onPressed: callback,
        child: hasLabel
            ? Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 17),
              )
            : Icon(
                cupertinoIconForSfSymbol(sfSymbol, fallback: icon),
                color: color,
                size: 20,
              ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: confirmTitle,
      message: '',
      actions: [
        const AdaptiveAlertAction<bool>(label: '取消', value: false),
        AdaptiveAlertAction<bool>(
          label: confirmLabel,
          value: true,
          isDestructive: destructive,
          isDefault: !destructive,
        ),
      ],
    );
    if (confirmed == true) onConfirmed();
  }
}
