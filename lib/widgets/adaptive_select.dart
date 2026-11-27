import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:techpie/theme/theme.dart';
import 'package:techpie/utils/platform.dart';
import 'package:techpie/widgets/ios/ios_native_select.dart';
import 'package:techpie/widgets/macos/macos_native_controls.dart';

class AdaptiveSelectOption {
  const AdaptiveSelectOption({
    required this.value,
    required this.label,
    this.sfSymbol,
    this.sfSymbolColor,
  });

  final String value;
  final String label;
  final String? sfSymbol;
  final Color? sfSymbolColor;
}

class AdaptiveSelect extends StatelessWidget {
  const AdaptiveSelect({
    super.key,
    required this.options,
    required this.onChanged,
    this.value,
    this.placeholder = 'Select',
    this.label,
    this.width = 150,
    this.height = iosMinimumInteractiveDimension,
    this.useIosNativeMenu = true,
    this.shrinkWrap = false,
    this.enabled = true,
    this.accessibilityLabel,
    this.iosButtonStyle = CNButtonStyle.glass,
    this.iosTint,
  });

  final List<AdaptiveSelectOption> options;
  final String? value;
  final ValueChanged<String> onChanged;
  final String placeholder;

  /// Optional field caption rendered alongside or above the selector in forms.
  final String? label;
  final double width;
  final double height;

  /// On iOS/macOS, a native pull-down/pop-up menu (`UIMenu` / `NSPopUpButton`).
  /// Off, the select is only a field showing the value: the caller wraps it in
  /// its own tap target and presents its own picker.
  final bool useIosNativeMenu;

  /// Native menu only: size the button to its label, as a value control in a
  /// list row is, instead of stretching to [width].
  final bool shrinkWrap;
  final bool enabled;
  final String? accessibilityLabel;
  final CNButtonStyle iosButtonStyle;
  final Color? iosTint;

  @override
  Widget build(BuildContext context) {
    if (!isApplePlatform()) {
      return _buildMaterialSelect(context);
    }

    final control = _buildControl(context);
    final fieldLabel = label;
    if (fieldLabel == null || fieldLabel.isEmpty) return control;

    final colors = context.tpColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fieldLabel,
          style: TpTypography.itemMeta(colors),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: TpTokens.space1),
        control,
      ],
    );
  }

  Widget _buildControl(BuildContext context) {
    if (usesMacOsNativeControls()) {
      return _buildMacOsControl(context);
    }
    if (!isIos()) return _buildMaterialSelect(context);

    final effectiveWidth = width < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : width;
    final effectiveHeight = height < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : height;
    if (useIosNativeMenu) {
      return IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.48,
          child: SizedBox(
            width: shrinkWrap ? null : effectiveWidth,
            height: effectiveHeight,
            child: IosNativeSelect(
              shrinkWrap: shrinkWrap,
              value: value,
              placeholder: placeholder,
              accessibilityLabel: accessibilityLabel ?? label ?? placeholder,
              buttonStyle: iosButtonStyle,
              tint: iosTint,
              options: [
                for (final option in options)
                  IosNativeSelectOption(
                    value: option.value,
                    label: option.label,
                    sfSymbol: option.sfSymbol,
                    sfSymbolColor: option.sfSymbolColor,
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
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

  Widget _buildMacOsControl(BuildContext context) {
    final selectedIndex = options.indexWhere((option) => option.value == value);
    if (!useIosNativeMenu) {
      final colors = context.tpColors;
      final selected = selectedIndex >= 0 ? options[selectedIndex] : null;
      return SizedBox(
        width: shrinkWrap ? null : width,
        height: 36,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceSubtle,
            borderRadius: BorderRadius.circular(TpTokens.radiusS),
            border: Border.all(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected?.label ?? placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TpTypography.itemTitle(colors).copyWith(
                      color: selected == null
                          ? colors.textMuted
                          : colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(TpIcons.expandMore, size: TpTokens.iconXs, color: colors.textMuted),
              ],
            ),
          ),
        ),
      );
    }

    final popup = MacosNativePopUpButton(
      items: [
        for (final option in options)
          MacosPopUpItem(
            label: option.label,
            sfSymbol: option.sfSymbol,
            checked: option.value == value,
          ),
      ],
      selectedIndex: selectedIndex,
      placeholder: placeholder,
      enabled: enabled && options.isNotEmpty,
      shrinkWrap: shrinkWrap,
      height: height < 36 ? height : 36,
      semanticLabel: accessibilityLabel ?? label ?? placeholder,
      onSelected: (index) {
        if (index >= 0 && index < options.length) {
          onChanged(options[index].value);
        }
      },
    );

    if (shrinkWrap) return popup;
    if (width.isFinite) {
      return SizedBox(width: width, child: popup);
    }
    return popup;
  }

  Widget _buildMaterialSelect(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    final selectedValue =
        options.any((option) => option.value == value) ? value : null;
    final fieldLabel = label;
    final hasLabel = fieldLabel != null && fieldLabel.isNotEmpty;

    final dropdown = DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        isExpanded: true,
        dropdownColor: colors.surface,
        focusColor: colors.brandSoft,
        borderRadius: radius,
        value: selectedValue,
        hint: hasLabel ? null : Text(placeholder),
        items: [
          for (final option in options)
            DropdownMenuItem<String>(
              value: option.value,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: enabled
            ? (selection) {
                if (selection != null) onChanged(selection);
              }
            : null,
      ),
    );

    final borderColor = colors.isDark
        ? colors.border
        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.45);

    if (hasLabel) {
      return Opacity(
        opacity: enabled ? 1.0 : 0.6,
        child: InputDecorator(
          isEmpty: selectedValue == null,
          decoration: InputDecoration(
            labelText: fieldLabel,
            filled: true,
            fillColor: colors.surfaceSubtle,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            border: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: borderColor),
            ),
          ),
          child: dropdown,
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceSubtle,
          borderRadius: radius,
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: dropdown,
        ),
      ),
    );
  }
}
