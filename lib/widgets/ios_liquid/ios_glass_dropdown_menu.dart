import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class IosGlassDropdownMenu extends StatefulWidget {
  const IosGlassDropdownMenu({
    super.key,
    required this.icon,
    required this.sfSymbol,
    required this.items,
    required this.onSelected,
    this.label,
    this.tooltip,
    this.width = 40,
    this.height = 40,
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
  State<IosGlassDropdownMenu> createState() => _IosGlassDropdownMenuState();
}

class _IosGlassDropdownMenuState extends State<IosGlassDropdownMenu> {
  MethodChannel? _channel;

  bool get _usesNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_usesNative) {
      return _buildFallback();
    }

    final signature = widget.items.map(_itemSignature).join(';');

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: UiKitView(
        key: ValueKey(
          'ios-glass-dropdown-$signature-${widget.sfSymbol}-${widget.label ?? ''}',
        ),
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: <String, Object?>{
          'sfSymbol': widget.sfSymbol,
          'label': widget.label,
          'items': [for (final item in widget.items) _encodeItem(item)],
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  Widget _buildFallback() {
    return PopupMenuButton<String>(
      tooltip: widget.tooltip,
      icon: Icon(widget.icon),
      onSelected: widget.onSelected,
      itemBuilder: (context) => [
        for (final item in widget.items)
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

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_channelPrefix/$viewId');
    _channel = channel;

    channel.setMethodCallHandler((call) async {
      if (call.method != 'onSelect') return null;

      final arguments = call.arguments;
      final value = arguments is Map ? arguments['value'] : null;

      if (value is String && value.isNotEmpty) {
        widget.onSelected(value);
      }

      return null;
    });
  }

  Map<String, Object?> _encodeItem(IosGlassDropdownMenuItem item) {
    return <String, Object?>{
      'value': item.value,
      'title': item.label,
      'checked': item.checked,
      'destructive': item.destructive,
      if (item.children != null)
        'children': [for (final child in item.children!) _encodeItem(child)],
    };
  }

  String _itemSignature(IosGlassDropdownMenuItem item) {
    final childrenSignature = item.children == null
        ? ''
        : item.children!.map(_itemSignature).join(',');
    return '${item.value}|${item.label}|${item.checked}|${item.destructive}|$childrenSignature';
  }
}

const _viewType = 'techpie/native_glass_dropdown_menu';
const _channelPrefix = 'techpie/native_glass_dropdown_menu';
