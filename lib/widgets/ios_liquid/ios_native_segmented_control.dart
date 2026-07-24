import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/platform.dart';

class IosNativeSegmentedControl extends StatefulWidget {
  const IosNativeSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final int value;
  final List<String> segments;
  final ValueChanged<int> onChanged;

  @override
  State<IosNativeSegmentedControl> createState() =>
      _IosNativeSegmentedControlState();
}

class _IosNativeSegmentedControlState extends State<IosNativeSegmentedControl> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant IosNativeSegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.segments.length != widget.segments.length ||
        !_sameSegments(oldWidget.segments, widget.segments)) {
      unawaited(_sendConfigurationUpdate());
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
    if (!isIos()) {
      return SegmentedButton<int>(
        segments: [
          for (var index = 0; index < widget.segments.length; index++)
            ButtonSegment<int>(
              value: index,
              label: Text(widget.segments[index]),
            ),
        ],
        selected: {widget.value},
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) widget.onChanged(selection.first);
        },
      );
    }

    return SizedBox(
      height: iosMinimumInteractiveDimension,
      child: UiKitView(
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  Map<String, Object?> get _configuration => <String, Object?>{
        'value': widget.value,
        'segments': widget.segments,
      };

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_channelPrefix/$viewId');
    _channel = channel;

    channel.setMethodCallHandler((call) async {
      if (call.method != 'onChanged') return null;

      final arguments = call.arguments as Map<Object?, Object?>?;
      final value = arguments?['value'];
      if (value is int) widget.onChanged(value);
      return null;
    });
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

  bool _sameSegments(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

const _viewType = 'techpie/native_segmented_control';
const _channelPrefix = 'techpie/native_segmented_control';
