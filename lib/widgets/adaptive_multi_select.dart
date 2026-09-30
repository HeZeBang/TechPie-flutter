import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';
import 'adaptive_select.dart';

/// [AdaptiveSelect]'s multi-choice sibling: the same field, opening a list of
/// checkboxes. The choice is applied on 确定, so 取消 means what it says.
class AdaptiveMultiSelect extends StatelessWidget {
  const AdaptiveMultiSelect({
    super.key,
    required this.options,
    required this.values,
    required this.onChanged,
    required this.summary,
    this.placeholder = '请选择',
    this.title,
    this.width,
    this.height = iosMinimumInteractiveDimension,
  });

  final List<AdaptiveSelectOption> options;
  final Set<String> values;
  final ValueChanged<Set<String>> onChanged;

  /// What the field reads while closed; the caller knows what is useful there.
  final String summary;

  final String placeholder;
  final String? title;
  final double? width;
  final double height;

  bool get _hasValues => values.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) return _buildMaterialField(context);

    final foreground = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return _field(
      context,
      background: CupertinoColors.secondarySystemFill.resolveFrom(context),
      radius: 10,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 10, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _hasValues ? summary : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _hasValues ? foreground : secondary,
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
    );
  }

  Widget _buildMaterialField(BuildContext context) {
    final theme = Theme.of(context);
    return _field(
      context,
      background: theme.colorScheme.surfaceContainerHigh,
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _hasValues ? summary : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: _hasValues
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required Color background,
    required double radius,
    required EdgeInsetsGeometry padding,
    required Widget child,
  }) {
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: options.isEmpty
              ? null
              : () => unawaited(_showOptions(context)),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    var pending = {...values};

    final confirmed = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('取消'),
                        ),
                        Expanded(
                          child: Text(
                            title ?? placeholder,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(sheetContext, pending),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options[index];
                          final selected = pending.contains(option.value);
                          return CheckboxListTile(
                            value: selected,
                            title: Text(option.label),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (checked) => setModalState(() {
                              if (checked ?? false) {
                                pending.add(option.value);
                              } else {
                                pending.remove(option.value);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != null) onChanged(confirmed);
  }
}
