import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IosGlassSwitch extends StatefulWidget {
  const IosGlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  State<IosGlassSwitch> createState() => _IosGlassSwitchState();
}

class _IosGlassSwitchState extends State<IosGlassSwitch> {
  MethodChannel? _channel;

  bool get _usesNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void didUpdateWidget(covariant IosGlassSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.value != widget.value) {
      _sendValueUpdate(widget.value);
    }

    if (oldWidget.enabled != widget.enabled) {
      _sendEnabledUpdate(widget.enabled);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_usesNative) {
      return Switch(
        value: widget.value,
        onChanged: widget.enabled ? widget.onChanged : null,
      );
    }

    return SizedBox(
      width: 52,
      height: 32,
      child: UiKitView(
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: <String, Object?>{
          'value': widget.value,
          'enabled': widget.enabled,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_channelPrefix/$viewId');
    _channel = channel;

    channel.setMethodCallHandler((call) async {
      if (call.method != 'onChanged') return null;

      final arguments = call.arguments;
      final value = arguments is Map ? arguments['value'] : null;

      if (value is bool) {
        widget.onChanged(value);
      }

      return null;
    });
  }

  Future<void> _sendValueUpdate(bool value) async {
    final channel = _channel;
    if (channel == null) return;

    try {
      await channel.invokeMethod<void>('updateValue', <String, Object?>{
        'value': value,
      });
    } on PlatformException {
      // Platform view may be tearing down.
    } on MissingPluginException {
      // Platform view may not be wired yet.
    }
  }

  Future<void> _sendEnabledUpdate(bool enabled) async {
    final channel = _channel;
    if (channel == null) return;

    try {
      await channel.invokeMethod<void>('updateEnabled', <String, Object?>{
        'enabled': enabled,
      });
    } on PlatformException {
      // Platform view may be tearing down.
    } on MissingPluginException {
      // Platform view may not be wired yet.
    }
  }
}

const _viewType = 'techpie/native_glass_switch';
const _channelPrefix = 'techpie/native_glass_switch';
