import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:techpie/utils/platform.dart';

class IosGlassConfirmationButton extends StatefulWidget {
  const IosGlassConfirmationButton({
    super.key,
    this.label,
    required this.confirmTitle,
    required this.confirmLabel,
    required this.onConfirmed,
    this.icon = Icons.link_off,
    this.sfSymbol = 'link.badge.minus',
    this.destructive = false,
    this.width,
    this.height = iosMinimumInteractiveDimension,
  });

  final String? label;
  final String confirmTitle;
  final String confirmLabel;
  final VoidCallback onConfirmed;
  final IconData icon;
  final String sfSymbol;
  final bool destructive;
  final double? width;
  final double height;

  @override
  State<IosGlassConfirmationButton> createState() =>
      _IosGlassConfirmationButtonState();
}

class _IosGlassConfirmationButtonState
    extends State<IosGlassConfirmationButton> {
  MethodChannel? _channel;

  bool get _usesNative => isIos();

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_usesNative) {
      if (widget.label == null || widget.label!.isEmpty) {
        return IconButton(
          onPressed: widget.onConfirmed,
          icon: Icon(widget.icon, size: 18),
          tooltip: widget.confirmTitle,
        );
      }

      return TextButton.icon(
        onPressed: widget.onConfirmed,
        icon: Icon(widget.icon, size: 18),
        label: Text(widget.label!),
      );
    }

    final requestedWidth = widget.width ??
        ((widget.label == null || widget.label!.isEmpty)
            ? iosMinimumInteractiveDimension
            : 92.0);
    final width = requestedWidth < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : requestedWidth;
    final height = widget.height < iosMinimumInteractiveDimension
        ? iosMinimumInteractiveDimension
        : widget.height;

    return SizedBox(
      width: width,
      height: height,
      child: UiKitView(
        key: ValueKey<String>(
          'ios-glass-confirm-${widget.label ?? ''}-'
          '${widget.confirmTitle}-${widget.confirmLabel}-'
          '${widget.sfSymbol}-${widget.destructive}',
        ),
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: <String, Object?>{
          'label': widget.label,
          'confirmTitle': widget.confirmTitle,
          'confirmLabel': widget.confirmLabel,
          'sfSymbol': widget.sfSymbol,
          'destructive': widget.destructive,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_channelPrefix/$viewId');
    _channel?.setMethodCallHandler(null);
    _channel = channel;

    channel.setMethodCallHandler((call) async {
      if (call.method != 'onConfirmed') return null;
      widget.onConfirmed();
      return null;
    });
  }
}

const _viewType = 'techpie/native_glass_confirmation_button';
const _channelPrefix = 'techpie/native_glass_confirmation_button';
