import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IosNativeTabBarItem {
  const IosNativeTabBarItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.sfSymbol,
    required this.selectedSfSymbol,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String sfSymbol;
  final String selectedSfSymbol;
}

class IosNativeTabBar extends StatefulWidget {
  const IosNativeTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<IosNativeTabBarItem> items;

  @override
  State<IosNativeTabBar> createState() => _IosNativeTabBarState();
}

class _IosNativeTabBarState extends State<IosNativeTabBar> {
  MethodChannel? _channel;

  int get _safeSelectedIndex {
    if (widget.items.isEmpty) return 0;
    return widget.selectedIndex.clamp(0, widget.items.length - 1);
  }

  @override
  void didUpdateWidget(covariant IosNativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    unawaited(_sendSelectionUpdate(_safeSelectedIndex));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const standardTabBarHeight = 49.0;
    final tabBarHeight = standardTabBarHeight + bottomInset;

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaWidth = MediaQuery.sizeOf(context).width;
        final constrainedWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : mediaWidth;
        final width = constrainedWidth.isFinite ? constrainedWidth : mediaWidth;

        if (width <= 40 || tabBarHeight <= 20) {
          return SizedBox(height: tabBarHeight);
        }

        final itemSignature = widget.items
            .map(
              (item) =>
                  '${item.label}|${item.sfSymbol}|${item.selectedSfSymbol}',
            )
            .join(';');

        return SizedBox(
          width: width,
          height: tabBarHeight,
          child: UiKitView(
            key: ValueKey(
              'ios-glass-tabbar-${width.round()}-${tabBarHeight.round()}-$itemSignature',
            ),
            viewType: _viewType,
            layoutDirection: Directionality.of(context),
            creationParams: <String, Object?>{
              'selectedIndex': _safeSelectedIndex,
              'items': [
                for (final item in widget.items)
                  <String, Object?>{
                    'label': item.label,
                    'sfSymbol': item.sfSymbol,
                    'selectedSfSymbol': item.selectedSfSymbol,
                  },
              ],
            },
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onPlatformViewCreated,
          ),
        );
      },
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_channelPrefix/$viewId');
    _channel = channel;

    channel.setMethodCallHandler((call) async {
      if (call.method != 'onSelect') return null;
      final arguments = call.arguments;
      final index = arguments is Map ? arguments['index'] : null;
      if (index is int && index >= 0 && index < widget.items.length) {
        widget.onSelected(index);
      }
      return null;
    });
  }

  Future<void> _sendSelectionUpdate(int index) async {
    final channel = _channel;
    if (channel == null) return;

    try {
      await channel.invokeMethod<void>('updateSelectedIndex', <String, Object?>{
        'index': index,
      });
    } on PlatformException {
      // Platform view may be tearing down.
    } on MissingPluginException {
      // Platform view may not be wired yet.
    }
  }
}

const _viewType = 'techpie/native_glass_tab_bar';
const _channelPrefix = 'techpie/native_glass_tab_bar';
