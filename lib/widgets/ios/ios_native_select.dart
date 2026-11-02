import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

class IosNativeSelectOption {
  const IosNativeSelectOption({
    required this.value,
    required this.label,
    this.sfSymbol,
  });

  final String value;
  final String label;
  final String? sfSymbol;
}

class IosNativeSelect extends StatelessWidget {
  const IosNativeSelect({
    super.key,
    required this.options,
    required this.onChanged,
    required this.placeholder,
    required this.accessibilityLabel,
    this.value,
    this.shrinkWrap = false,
  });

  final List<IosNativeSelectOption> options;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final String accessibilityLabel;
  final String? value;

  /// Size the button to its label instead of the width it is given.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((option) => option.value == value).firstOrNull;
    return IgnorePointer(
      ignoring: options.isEmpty,
      child: CNPopupMenuButton(
        buttonLabel: selected?.label ?? placeholder,
        semanticLabel: accessibilityLabel,
        height: 44,
        shrinkWrap: shrinkWrap,
        // UIMenu otherwise reverses its items when it opens upwards, so the
        // same list would read in two orders depending on where it sits.
        preserveTopToBottomOrder: true,
        buttonStyle: CNButtonStyle.glass,
        tint: Theme.of(context).colorScheme.onSurface,
        items: [
          for (final option in options)
            CNPopupMenuItem(
              label: option.label,
              // Match UIMenu's default size on both creation and updates.
              icon: option.sfSymbol == null ? null : CNSymbol(option.sfSymbol!, size: 0),
              checked: option.value == value,
            ),
        ],
        onSelected: (index) {
          if (index >= 0 && index < options.length) {
            onChanged(options[index].value);
          }
        },
      ),
    );
  }
}
