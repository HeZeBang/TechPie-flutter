import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/platform.dart';
import 'secure_password_field.dart';

class AdaptiveTextFieldGroupItem {
  const AdaptiveTextFieldGroupItem({
    required this.controller,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.obscureText = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
}

class AdaptiveTextFieldGroup extends StatelessWidget {
  const AdaptiveTextFieldGroup({
    super.key,
    required this.items,
    this.embedded = false,
  });

  final List<AdaptiveTextFieldGroupItem> items;

  /// Whether this group sits inside a white surface card (`TpCard`) rather
  /// than directly on the canvas background.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) {
      return Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: TpTokens.space3),
            _buildMaterialField(items[i]),
          ],
        ],
      );
    }

    final colors = context.tpColors;
    final background = embedded ? colors.surfaceSubtle : colors.surface;
    final borderColor = colors.isDark ? colors.border : colors.divider;
    final separator = colors.divider;
    final radius = BorderRadius.circular(TpTokens.radiusS);

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 0.75),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(color: background),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < items.length; index++) ...[
                _buildCupertinoField(context, items[index]),
                if (index < items.length - 1)
                  SizedBox(
                    height: 1,
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 16,
                      endIndent: 16,
                      color: separator,
                    ),
                  ),
              ],
            ],
          ),
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
      child: item.obscureText
          ? SecurePasswordField(
              controller: item.controller,
              placeholder: item.placeholder,
              enabled: item.enabled,
              textInputAction: item.textInputAction,
              onChanged: item.onChanged,
              onSubmitted: item.onSubmitted,
            )
          : CupertinoTextField(
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
              onChanged: item.onChanged,
              onSubmitted: item.onSubmitted,
            ),
    );
  }

  Widget _buildMaterialField(AdaptiveTextFieldGroupItem item) {
    if (item.obscureText) {
      return SecurePasswordField(
        controller: item.controller,
        placeholder: item.placeholder,
        enabled: item.enabled,
        textInputAction: item.textInputAction,
        onChanged: item.onChanged,
        onSubmitted: item.onSubmitted,
      );
    }
    return TextField(
      controller: item.controller,
      decoration: InputDecoration(hintText: item.placeholder),
      keyboardType: item.keyboardType,
      textInputAction: item.textInputAction,
      obscureText: item.obscureText,
      enabled: item.enabled,
      onChanged: item.onChanged,
      onSubmitted: item.onSubmitted,
    );
  }
}
