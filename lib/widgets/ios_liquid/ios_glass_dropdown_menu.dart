import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:techpie/utils/platform.dart';

import 'ios_symbol_icons.dart';

class IosGlassDropdownMenuItem {
  const IosGlassDropdownMenuItem({
    required this.value,
    required this.label,
    this.checked = false,
    this.destructive = false,
    this.children,
  });

  final String value;
  final String label;
  final bool checked;
  final bool destructive;
  final List<IosGlassDropdownMenuItem>? children;
}

class IosGlassDropdownMenu extends StatelessWidget {
  const IosGlassDropdownMenu({
    super.key,
    required this.icon,
    required this.sfSymbol,
    required this.items,
    required this.onSelected,
    this.label,
    this.tooltip,
    this.width = iosMinimumInteractiveDimension,
    this.height = iosMinimumInteractiveDimension,
  });

  final IconData icon;
  final String sfSymbol;
  final List<IosGlassDropdownMenuItem> items;
  final ValueChanged<String> onSelected;
  final String? label;
  final String? tooltip;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) return _buildMaterialMenu();

    final effectiveWidth = width < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : width;
    final effectiveHeight = height < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : height;
    final hasLabel = label != null && label!.isNotEmpty;

    return Semantics(
      button: true,
      label: tooltip ?? label,
      child: SizedBox(
        width: effectiveWidth,
        height: effectiveHeight,
        child: CupertinoButton(
          minSize: iosMinimumInteractiveDimension,
          padding: EdgeInsets.symmetric(horizontal: hasLabel ? 10 : 0),
          onPressed:
              items.isEmpty ? null : () async => _showMenu(context, items),
          child: hasLabel
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      iosIconForSfSymbol(sfSymbol, fallback: icon),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Icon(
                  iosIconForSfSymbol(sfSymbol, fallback: icon),
                  size: 20,
                ),
        ),
      ),
    );
  }

  Widget _buildMaterialMenu() {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      icon: Icon(icon),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final item in items)
          item.checked
              ? CheckedPopupMenuItem<String>(
                  value: item.value,
                  checked: true,
                  child: Text(
                    item.label,
                    style: item.destructive
                        ? TextStyle(color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
                )
              : PopupMenuItem<String>(
                  value: item.value,
                  child: Text(
                    item.label,
                    style: item.destructive
                        ? TextStyle(color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
                ),
      ],
    );
  }

  Future<void> _showMenu(
    BuildContext context,
    List<IosGlassDropdownMenuItem> menuItems, {
    String? title,
  }) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final item in menuItems)
            CupertinoActionSheetAction(
              isDestructiveAction: item.destructive,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                final children = item.children;
                if (children != null && children.isNotEmpty) {
                  Future<void>.microtask(() {
                    if (context.mounted) {
                      _showMenu(context, children, title: item.label);
                    }
                  });
                } else {
                  onSelected(item.value);
                }
              },
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: item.checked
                        ? const Icon(CupertinoIcons.check_mark, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.label)),
                  if (item.children?.isNotEmpty ?? false)
                    const Icon(CupertinoIcons.chevron_forward, size: 16),
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
