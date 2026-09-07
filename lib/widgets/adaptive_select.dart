import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:techpie/utils/platform.dart';

class AdaptiveSelectOption {
  const AdaptiveSelectOption({required this.value, required this.label});

  final String value;
  final String label;
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
  });

  final List<AdaptiveSelectOption> options;
  final String? value;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) return _buildMaterialSelect(context);

    final effectiveWidth = width < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : width;
    final effectiveHeight = height < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : height;
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
        child: CupertinoButton(
          // Retain Flutter 3.27 compatibility; minimumSize was added later.
          // ignore: deprecated_member_use
          minSize: iosMinimumInteractiveDimension,
          padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 10, 0),
          borderRadius: BorderRadius.circular(10),
          onPressed: options.isEmpty ? null : () async => _showOptions(context),
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

  Future<void> _showOptions(BuildContext context) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          for (final option in options)
            CupertinoActionSheetAction(
              isDefaultAction: option.value == value,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                onChanged(option.value);
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: option.value == value
                        ? const Icon(CupertinoIcons.check_mark, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(option.label)),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }
}
