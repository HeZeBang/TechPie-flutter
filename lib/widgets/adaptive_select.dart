import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:techpie/utils/platform.dart';
import 'package:techpie/widgets/ios/ios_native_select.dart';

class AdaptiveSelectOption {
  const AdaptiveSelectOption({
    required this.value,
    required this.label,
    this.sfSymbol,
  });

  final String value;
  final String label;
  final String? sfSymbol;
}

class AdaptiveSelect extends StatelessWidget {
  const AdaptiveSelect({
    super.key,
    required this.options,
    required this.onChanged,
    this.value,
    this.placeholder = 'Select',
    this.width = 150,
    this.height = iosMinimumInteractiveDimension,
    this.useIosNativeMenu = true,
    this.shrinkWrap = false,
    this.accessibilityLabel,
  });

  final List<AdaptiveSelectOption> options;
  final String? value;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final double width;
  final double height;
  /// On iOS, a native pull-down menu (UIMenu). Off, the select is only a
  /// field showing the value: the caller wraps it in its own tap target and
  /// presents its own picker (the course editor's wheel sheets do).
  final bool useIosNativeMenu;

  /// iOS native menu only: size the button to its label, as a value control
  /// in a list row is, instead of [width].
  final bool shrinkWrap;
  final String? accessibilityLabel;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) return _buildMaterialSelect(context);

    final effectiveWidth = width < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : width;
    final effectiveHeight = height < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : height;
    if (useIosNativeMenu) {
      return SizedBox(
        width: shrinkWrap ? null : effectiveWidth,
        height: effectiveHeight,
        child: IosNativeSelect(
          shrinkWrap: shrinkWrap,
          value: value,
          placeholder: placeholder,
          accessibilityLabel: accessibilityLabel ?? placeholder,
          options: [
            for (final option in options)
              IosNativeSelectOption(
                value: option.value,
                label: option.label,
                sfSymbol: option.sfSymbol,
              ),
          ],
          onChanged: onChanged,
        ),
      );
    }
    final selected =
        options.where((option) => option.value == value).firstOrNull;
    final foreground = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return SizedBox(
      width: effectiveWidth,
      height: effectiveHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 10, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected?.label ?? placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected == null ? secondary : foreground,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_up_chevron_down,
                size: 14,
                color: secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialSelect(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value:
                options.any((option) => option.value == value) ? value : null,
            hint: Text(placeholder),
            items: [
              for (final option in options)
                DropdownMenuItem<String>(
                  value: option.value,
                  child: Text(option.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (selection) {
              if (selection != null) onChanged(selection);
            },
          ),
        ),
      ),
    );
  }
}
