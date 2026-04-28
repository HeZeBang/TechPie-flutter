import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeGlassFloatingButton extends StatefulWidget {
  const NativeGlassFloatingButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.sfSymbol,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String sfSymbol;

  @override
  State<NativeGlassFloatingButton> createState() =>
      _NativeGlassFloatingButtonState();
}

class _NativeGlassFloatingButtonState extends State<NativeGlassFloatingButton> {
  MethodChannel? _channel;

  bool get _usesNativeButton =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void didUpdateWidget(covariant NativeGlassFloatingButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_usesNativeButton) return;
    if (oldWidget.sfSymbol == widget.sfSymbol) return;

    _sendSymbolUpdate(widget.sfSymbol);
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_usesNativeButton) {
      return FloatingActionButton(
        onPressed: widget.onPressed,
        child: Icon(widget.icon),
      );
    }

    return SizedBox.square(
      dimension: 64,
      child: UiKitView(
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: <String, Object?>{'sfSymbol': widget.sfSymbol},
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

      widget.onPressed();
      return null;
    });
  }

  Future<void> _sendSymbolUpdate(String sfSymbol) async {
    final channel = _channel;
    if (channel == null) return;

    try {
      await channel.invokeMethod<void>('updateSymbol', <String, Object?>{
        'sfSymbol': sfSymbol,
      });
    } on PlatformException {
      // Platform view may be tearing down.
    } on MissingPluginException {
      // Platform view may not be wired yet.
    }
  }
}

const _viewType = 'techpie/native_glass_floating_button';
const _channelPrefix = 'techpie/native_glass_floating_button';
