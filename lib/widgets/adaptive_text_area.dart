import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/platform.dart';

class AdaptiveTextArea extends StatelessWidget {
  const AdaptiveTextArea({
    super.key,
    required this.controller,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.minLines = 1,
    this.maxLines = 1,
    this.enabled = true,
    this.embedded = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final bool embedded;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) {
      return TextField(
        controller: controller,
        decoration: InputDecoration(hintText: placeholder),
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        minLines: minLines,
        maxLines: maxLines,
        enabled: enabled,
        onChanged: onChanged,
      );
    }

    final colors = context.tpColors;
    final background = embedded ? colors.surfaceSubtle : colors.surface;
    final borderColor = colors.isDark ? colors.border : colors.divider;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 108),
      child: CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        minLines: minLines,
        maxLines: maxLines,
        enabled: enabled,
        padding: const EdgeInsets.all(14),
        textAlignVertical: TextAlignVertical.top,
        clearButtonMode: OverlayVisibilityMode.editing,
        onChanged: onChanged,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(TpTokens.radiusS),
          border: Border.all(color: borderColor, width: 0.75),
        ),
      ),
    );
  }
}
