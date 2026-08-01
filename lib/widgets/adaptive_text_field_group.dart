import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';

class AdaptiveTextFieldGroupItem {
  const AdaptiveTextFieldGroupItem({
    required this.controller,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.obscureText = false,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
}

class AdaptiveTextFieldGroup extends StatelessWidget {
  const AdaptiveTextFieldGroup({super.key, required this.items});

  final List<AdaptiveTextFieldGroupItem> items;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) {
      return Column(
        children: [for (final item in items) _buildMaterialField(item)],
      );
    }

    final background =
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(color: background),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < items.length; index++) ...[
              _buildCupertinoField(context, items[index]),
              if (index < items.length - 1)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16),
                  child: Container(height: 0.5, color: separator),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoField(
    BuildContext context,
    AdaptiveTextFieldGroupItem item,
  ) {
    return SizedBox(
      height: 56,
      child: CupertinoTextField(
        controller: item.controller,
        placeholder: item.placeholder,
        keyboardType: item.keyboardType,
        textInputAction: item.textInputAction,
        obscureText: item.obscureText,
        enabled: item.enabled,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(),
        clearButtonMode: item.obscureText
            ? OverlayVisibilityMode.never
            : OverlayVisibilityMode.editing,
        onSubmitted: (value) {
          if (item.textInputAction == TextInputAction.next) {
            FocusScope.of(context).nextFocus();
          }
          item.onSubmitted?.call(value);
        },
      ),
    );
  }

  Widget _buildMaterialField(AdaptiveTextFieldGroupItem item) {
    return TextField(
      controller: item.controller,
      decoration: InputDecoration(hintText: item.placeholder),
      keyboardType: item.keyboardType,
      textInputAction: item.textInputAction,
      obscureText: item.obscureText,
      enabled: item.enabled,
      onSubmitted: item.onSubmitted,
    );
  }
}
