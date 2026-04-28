import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeGlassTabBarItem {
  const NativeGlassTabBarItem({
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

class NativeGlassTabBar extends StatefulWidget {
  const NativeGlassTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NativeGlassTabBarItem> items;

  @override
  State<NativeGlassTabBar> createState() => _NativeGlassTabBarState();
}

class _NativeGlassTabBarState extends State<NativeGlassTabBar> {
  MethodChannel? _channel;

  bool get _usesNativeBar =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  int get _safeSelectedIndex {
    if (widget.items.isEmpty) return 0;
    return widget.selectedIndex.clamp(0, widget.items.length - 1);
  }

  @override
  void didUpdateWidget(covariant NativeGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_usesNativeBar) return;
    if (oldWidget.selectedIndex == widget.selectedIndex) return;

    _sendSelectionUpdate(_safeSelectedIndex);
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_usesNativeBar) {
      return NavigationBar(
        selectedIndex: _safeSelectedIndex,
        onDestinationSelected: widget.onSelected,
        destinations: [
          for (final item in widget.items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      );
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: SizedBox(
        height: 78,
        child: UiKitView(
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
      ),
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
