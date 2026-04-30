import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IosGlassSelectOption {
  const IosGlassSelectOption({required this.value, required this.label});

  final String value;
  final String label;
}

class IosGlassSelect extends StatefulWidget {
  const IosGlassSelect({
    super.key,
    required this.options,
    required this.onChanged,
    this.value,
    this.placeholder = 'Select',
    this.sfSymbol = 'chevron.up.chevron.down',
    this.width = 150,
    this.height = 36,
  });

  final List<IosGlassSelectOption> options;
  final String? value;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final String sfSymbol;
  final double width;
  final double height;

  @override
  State<IosGlassSelect> createState() => _IosGlassSelectState();
}

class _IosGlassSelectState extends State<IosGlassSelect> {
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
      return _buildFallback(context);
    }

    final signature = widget.options
        .map((option) => '${option.value}|${option.label}')
        .join(';');

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: UiKitView(
        key: ValueKey(
          'ios-glass-select-$signature-${widget.value ?? ''}-${widget.placeholder}',
        ),
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: <String, Object?>{
          'value': widget.value,
          'placeholder': widget.placeholder,
          'sfSymbol': widget.sfSymbol,
          'options': [
            for (final option in widget.options)
              <String, Object?>{'value': option.value, 'label': option.label},
          ],
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
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
            value: widget.options.any((option) => option.value == widget.value)
                ? widget.value
                : null,
            hint: Text(widget.placeholder),
            items: [
              for (final option in widget.options)
                DropdownMenuItem<String>(
                  value: option.value,
                  child: Text(option.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                widget.onChanged(value);
              }
            },
          ),
        ),
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

      if (value is String && value.isNotEmpty) {
        widget.onChanged(value);
      }

      return null;
    });
  }
}

const _viewType = 'techpie/native_glass_select';
const _channelPrefix = 'techpie/native_glass_select';
