import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IosNativeSelectOption {
  const IosNativeSelectOption({
    required this.value,
    required this.label,
    this.sfSymbol,
  });

  final String value;
  final String label;
  final String? sfSymbol;

  Map<String, Object?> toMap() =>
      {'value': value, 'label': label, 'sfSymbol': sfSymbol};
}

class IosNativeSelect extends StatefulWidget {
  const IosNativeSelect({
    super.key,
    required this.options,
    required this.onChanged,
    required this.placeholder,
    required this.accessibilityLabel,
    this.value,
  });

  final List<IosNativeSelectOption> options;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final String accessibilityLabel;
  final String? value;

  @override
  State<IosNativeSelect> createState() => _IosNativeSelectState();
}

class _IosNativeSelectState extends State<IosNativeSelect> {
  MethodChannel? _channel;
  Brightness _brightness = Brightness.light;

  Map<String, Object?> _selectionConfiguration(IosNativeSelect widget) => {
        'value': widget.value,
        'placeholder': widget.placeholder,
        'accessibilityLabel': widget.accessibilityLabel,
        'options': widget.options.map((option) => option.toMap()).toList(),
      };

  Map<String, Object?> get _configuration => {
        ..._selectionConfiguration(widget),
        'brightness': _brightness.name,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness == brightness) return;
    _brightness = brightness;
    final channel = _channel;
    if (channel != null) unawaited(_updateConfiguration(channel));
  }

  @override
  void didUpdateWidget(covariant IosNativeSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    final channel = _channel;
    if (channel != null &&
        jsonEncode(_selectionConfiguration(oldWidget)) !=
            jsonEncode(_selectionConfiguration(widget))) {
      unawaited(_updateConfiguration(channel));
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiKitView(
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );

  Future<void> _updateConfiguration(MethodChannel channel) async {
    try {
      await channel.invokeMethod<void>('updateConfiguration', _configuration);
    } on PlatformException {
      // The platform view may be tearing down.
    } on MissingPluginException {
      // The platform view may not be wired yet.
    }
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_viewType/$viewId');
    _channel?.setMethodCallHandler(null);
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'onChanged' || call.arguments is! Map) return;
      final arguments = call.arguments as Map<Object?, Object?>;
      final value = arguments['value'];
      if (value is String &&
          widget.options.any((option) => option.value == value)) {
        widget.onChanged(value);
      }
    });
    unawaited(_updateConfiguration(channel));
  }
}

const _viewType = 'techpie/native_select';
