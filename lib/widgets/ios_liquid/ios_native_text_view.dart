import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/platform.dart';

class IosNativeTextView extends StatelessWidget {
  const IosNativeTextView({
    super.key,
    required this.controller,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.minLines = 1,
    this.maxLines = 1,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final int minLines;
  final int maxLines;
  final bool enabled;

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
      );
    }

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
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
