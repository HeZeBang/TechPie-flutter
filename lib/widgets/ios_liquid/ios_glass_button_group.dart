import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IosGlassButtonGroupButton {
  const IosGlassButtonGroupButton({
    required this.id,
    required this.icon,
    required this.sfSymbol,
    this.tooltip,
  });

  final String id;
  final IconData icon;
  final String sfSymbol;
  final String? tooltip;
}

class IosGlassButtonGroup extends StatefulWidget {
  const IosGlassButtonGroup({
    super.key,
    required this.buttons,
    required this.onPressed,
    this.height = 40,
    this.width,
  });

  final List<IosGlassButtonGroupButton> buttons;
  final ValueChanged<String> onPressed;
  final double height;
  final double? width;

  @override
  State<IosGlassButtonGroup> createState() => _IosGlassButtonGroupState();
}

class _IosGlassButtonGroupState extends State<IosGlassButtonGroup> {
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
    if (widget.buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!_usesNative) {
      return _buildFallback(context);
    }

    final signature = widget.buttons
        .map(
          (button) => '${button.id}|${button.sfSymbol}|${button.tooltip ?? ''}',
        )
        .join(';');

    final width = widget.width ?? widget.buttons.length * 44.0;

    return SizedBox(
      width: width,
      height: widget.height,
      child: UiKitView(
        key: ValueKey(
          'ios-glass-button-group-$signature-${widget.height}-$width',
        ),
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: <String, Object?>{
          'buttons': [
            for (final button in widget.buttons)
              <String, Object?>{
                'id': button.id,
                'sfSymbol': button.sfSymbol,
                'accessibilityLabel': button.tooltip,
              },
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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final button in widget.buttons)
            Expanded(
              child: IconButton(
                tooltip: button.tooltip,
                icon: Icon(button.icon, size: 18),
                onPressed: () => widget.onPressed(button.id),
              ),
            ),
        ],
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_channelPrefix/$viewId');
    _channel = channel;

    channel.setMethodCallHandler((call) async {
      if (call.method != 'onTap') return null;

      final arguments = call.arguments;
      final id = arguments is Map ? arguments['id'] : null;

      if (id is String && id.isNotEmpty) {
        widget.onPressed(id);
      }

      return null;
    });
  }
}

const _viewType = 'techpie/native_glass_button_group';
const _channelPrefix = 'techpie/native_glass_button_group';
