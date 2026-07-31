import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:techpie/utils/platform.dart';

enum IosNativeNavigationBarItemRole { normal, done, destructive }

class IosNativeNavigationBarItem {
  const IosNativeNavigationBarItem({
    required this.id,
    this.title,
    this.sfSymbol,
    this.role = IosNativeNavigationBarItemRole.normal,
    this.enabled = true,
    this.hidden = false,
    this.accessibilityLabel,
    this.placementGroup,
    this.menuItems = const [],
  });

  final String id;
  final String? title;
  final String? sfSymbol;
  final IosNativeNavigationBarItemRole role;
  final bool enabled;
  final bool hidden;
  final String? accessibilityLabel;
  final String? placementGroup;
  final List<IosNativeNavigationBarMenuItem> menuItems;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'sfSymbol': sfSymbol,
      'role': role.name,
      'enabled': enabled,
      'hidden': hidden,
      'accessibilityLabel': accessibilityLabel,
      'placementGroup': placementGroup,
      'menuItems': menuItems.map((item) => item.toMap()).toList(),
    };
  }
}

class IosNativeNavigationBarMenuItem {
  const IosNativeNavigationBarMenuItem({
    required this.value,
    required this.title,
    this.sfSymbol,
    this.checked = false,
    this.destructive = false,
    this.displayInline = false,
    this.children = const [],
  });

  final String value;
  final String title;
  final String? sfSymbol;
  final bool checked;
  final bool destructive;
  final bool displayInline;
  final List<IosNativeNavigationBarMenuItem> children;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'value': value,
      'title': title,
      'sfSymbol': sfSymbol,
      'checked': checked,
      'destructive': destructive,
      'displayInline': displayInline,
      'children': children.map((item) => item.toMap()).toList(),
    };
  }
}

class IosNativeNavigationBar extends StatefulWidget
    implements PreferredSizeWidget {
  const IosNativeNavigationBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingItems = const [],
    this.trailingItems = const [],
    this.selectionMode = false,
    this.largeTitleMode = false,
    this.onItemPressed,
    this.onMenuSelected,
  });

  final String title;
  final String? subtitle;
  final List<IosNativeNavigationBarItem> leadingItems;
  final List<IosNativeNavigationBarItem> trailingItems;
  final bool selectionMode;
  final bool largeTitleMode;
  final ValueChanged<String>? onItemPressed;
  final void Function(String id, String value)? onMenuSelected;

  @override
  Size get preferredSize => Size.fromHeight(_barHeight);

  double get _barHeight {
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    if (largeTitleMode) {
      return hasSubtitle && usesIosLiquidGlass() ? 112.0 : 96.0;
    }
    return hasSubtitle ? 56.0 : 44.0;
  }

  @override
  State<IosNativeNavigationBar> createState() => _IosNativeNavigationBarState();
}

class _IosNativeNavigationBarState extends State<IosNativeNavigationBar> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant IosNativeNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final channel = _channel;
    if (channel == null || !_configurationChanged(oldWidget)) return;
    unawaited(_sendConfigurationUpdate(channel));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isIos()) return AppBar(title: Text(widget.title));

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: widget._barHeight,
        child: UiKitView(
          viewType: _viewType,
          layoutDirection: Directionality.of(context),
          creationParams: _configuration,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      ),
    );
  }

  bool _configurationChanged(IosNativeNavigationBar oldWidget) {
    return _signature(oldWidget) != _signature(widget);
  }

  Object _signature(IosNativeNavigationBar widget) {
    return jsonEncode(<String, Object?>{
      'title': widget.title,
      'subtitle': widget.subtitle,
      'leadingItems': widget.leadingItems.map((item) => item.toMap()).toList(),
      'trailingItems':
          widget.trailingItems.map((item) => item.toMap()).toList(),
      'selectionMode': widget.selectionMode,
      'largeTitleMode': widget.largeTitleMode,
    });
  }

  Map<String, Object?> get _configuration => <String, Object?>{
        'title': widget.title,
        'subtitle': widget.subtitle,
        'leadingItems':
            widget.leadingItems.map((item) => item.toMap()).toList(),
        'trailingItems':
            widget.trailingItems.map((item) => item.toMap()).toList(),
        'selectionMode': widget.selectionMode,
        'largeTitleMode': widget.largeTitleMode,
      };

  Future<void> _sendConfigurationUpdate(MethodChannel channel) async {
    try {
      await channel.invokeMethod<void>('updateConfiguration', _configuration);
    } on PlatformException {
      // Platform view may be tearing down.
    } on MissingPluginException {
      // Platform view may not be wired yet.
    }
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_channelPrefix/$viewId');
    _channel?.setMethodCallHandler(null);
    _channel = channel;

    channel.setMethodCallHandler((call) async {
      final arguments = call.arguments as Map<Object?, Object?>?;
      switch (call.method) {
        case 'onItemPressed':
          final id = arguments?['id'] as String?;
          if (id != null) widget.onItemPressed?.call(id);
        case 'onMenuSelected':
          final id = arguments?['id'] as String?;
          final value = arguments?['value'] as String?;
          if (id != null && value != null) {
            widget.onMenuSelected?.call(id, value);
          }
      }
      return null;
    });
  }
}

const _viewType = 'techpie/native_navigation_bar';
const _channelPrefix = 'techpie/native_navigation_bar';
