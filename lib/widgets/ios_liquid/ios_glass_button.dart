import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:techpie/utils/platform.dart';

enum IosNativeButtonRole { prominent, standard, plain, destructive }

class IosGlassButton extends StatefulWidget {
  const IosGlassButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.sfSymbol,
    this.label,
    this.subtitle,
    this.role = IosNativeButtonRole.standard,
    this.loading = false,
    this.width,
    this.height,
    this.accessibilityLabel,
    this.showIosIcon = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String sfSymbol;
  final String? label;
  final String? subtitle;
  final IosNativeButtonRole role;
  final bool loading;
  final double? width;
  final double? height;
  final String? accessibilityLabel;
  final bool showIosIcon;

  @override
  State<IosGlassButton> createState() => _IosGlassButtonState();
}

class _IosGlassButtonState extends State<IosGlassButton> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant IosGlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(oldWidget) == _signature(widget)) return;
    unawaited(_sendConfigurationUpdate());
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isIos()) {
      return _buildMaterialButton(context);
    }

    final hasLabel = widget.label != null && widget.label!.isNotEmpty;
    return SizedBox(
      width: widget.width ?? (hasLabel ? double.infinity : 44),
      height: widget.height ?? 44,
      child: UiKitView(
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_channelPrefix/$viewId');
    _channel = channel;

    channel.setMethodCallHandler((call) async {
      if (call.method != 'onTap') return null;

      widget.onPressed?.call();
      return null;
    });
  }

  Map<String, Object?> get _configuration => <String, Object?>{
        'sfSymbol': widget.sfSymbol,
        'label': widget.label,
        'subtitle': widget.subtitle,
        'role': widget.role.name,
        'enabled': widget.onPressed != null,
        'loading': widget.loading,
        'accessibilityLabel': widget.accessibilityLabel,
        'showsIcon':
            widget.label == null || widget.label!.isEmpty || widget.showIosIcon,
      };

  String _signature(IosGlassButton value) => jsonEncode(<String, Object?>{
        'sfSymbol': value.sfSymbol,
        'label': value.label,
        'subtitle': value.subtitle,
        'role': value.role.name,
        'enabled': value.onPressed != null,
        'loading': value.loading,
        'accessibilityLabel': value.accessibilityLabel,
        'showsIcon':
            value.label == null || value.label!.isEmpty || value.showIosIcon,
      });

  Widget _buildMaterialButton(BuildContext context) {
    final label = widget.label;
    if (label == null || label.isEmpty) {
      return IconButton.filled(
        onPressed: widget.onPressed,
        icon: widget.loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(widget.icon),
      );
    }

    final foreground = widget.role == IosNativeButtonRole.destructive
        ? Theme.of(context).colorScheme.error
        : null;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(widget.icon),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              if (widget.subtitle != null)
                Text(
                  widget.subtitle!,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ],
    );
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size.fromHeight(widget.height ?? 56),
      ),
      foregroundColor:
          foreground == null ? null : WidgetStatePropertyAll(foreground),
    );

    return switch (widget.role) {
      IosNativeButtonRole.prominent =>
        FilledButton(onPressed: widget.onPressed, style: style, child: child),
      IosNativeButtonRole.standard => FilledButton.tonal(
          onPressed: widget.onPressed,
          style: style,
          child: child,
        ),
      IosNativeButtonRole.plain ||
      IosNativeButtonRole.destructive =>
        TextButton(onPressed: widget.onPressed, style: style, child: child),
    };
  }

  Future<void> _sendConfigurationUpdate() async {
    final channel = _channel;
    if (channel == null) return;

    try {
      await channel.invokeMethod<void>('updateConfiguration', _configuration);
    } on PlatformException {
      // Platform view may be tearing down.
    } on MissingPluginException {
      // Platform view may not be wired yet.
    }
  }
}

const _viewType = 'techpie/native_glass_button';
const _channelPrefix = 'techpie/native_glass_button';
