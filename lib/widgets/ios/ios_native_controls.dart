import 'dart:async';

import 'package:cupertino_native_better/utils/modal_hide_mixin.dart';
import 'package:flutter/cupertino.dart' show CupertinoDynamicColor;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void _swallowMissingPlugin(Future<Object?> future) {
  unawaited(
    future.catchError((Object error) {
      if (error is MissingPluginException || error is PlatformException) {
        return null;
      }
      throw error;
    }),
  );
}

int _resolveArgb(Color color, BuildContext context) =>
    CupertinoDynamicColor.resolve(color, context).toARGB32();

/// Direct UIKit `UISwitch` platform view for pre-iOS 26 devices/simulators,
/// bypassing `CNSwitch`'s `iOS >= 26` Liquid Glass gate so iOS 15–25 still uses
/// authentic native controls rather than Flutter-drawn switches.
class IosDirectNativeSwitch extends StatefulWidget {
  const IosDirectNativeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.height = 44.0,
    this.color,
    this.semanticLabel,
    this.autoHideOnModal = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final double height;
  final Color? color;
  final String? semanticLabel;
  final bool autoHideOnModal;

  @override
  State<IosDirectNativeSwitch> createState() => _IosDirectNativeSwitchState();
}

class _IosDirectNativeSwitchState extends State<IosDirectNativeSwitch>
    with ModalHideMixin<IosDirectNativeSwitch> {
  static const _viewType = 'CupertinoNativeSwitch';

  MethodChannel? _channel;
  bool? _lastValue;
  bool? _lastEnabled;
  String? _lastSemanticLabel;
  bool? _lastIsDark;
  int? _lastTint;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _effectiveColor =>
      widget.color ?? Theme.of(context).colorScheme.primary;

  @override
  bool get autoHideOnModal => widget.autoHideOnModal;

  @override
  MethodChannel? get platformViewChannel => _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IosDirectNativeSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncProps();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightness();
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('${_viewType}_$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'valueChanged') {
        final args = call.arguments as Map<Object?, Object?>?;
        final next = args?['value'] as bool?;
        if (next != null) {
          _lastValue = next;
          // CupertinoSwitchPlatformView uses SwiftUI `.onChange`, which fires
          // when Dart invokes `setValue`. Ignore echoes matching current state.
          if (next != widget.value) {
            widget.onChanged(next);
          }
        }
      }
      return null;
    });
    _lastValue = widget.value;
    _lastEnabled = widget.enabled;
    _lastSemanticLabel = widget.semanticLabel;
    _lastIsDark = _isDark;
    _lastTint = _resolveArgb(_effectiveColor, context);
  }

  void _syncProps() {
    final ch = _channel;
    if (ch == null) return;
    final tint = _resolveArgb(_effectiveColor, context);
    if (_lastEnabled != widget.enabled) {
      _lastEnabled = widget.enabled;
      _swallowMissingPlugin(ch.invokeMethod<void>('setEnabled', {'enabled': widget.enabled}));
    }
    if (_lastSemanticLabel != widget.semanticLabel) {
      _lastSemanticLabel = widget.semanticLabel;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setSemanticLabel', {'label': widget.semanticLabel}),
      );
    }
    if (_lastValue != widget.value) {
      _lastValue = widget.value;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setValue', {'value': widget.value, 'animated': true}),
      );
    }
    if (_lastTint != tint) {
      _lastTint = tint;
      _swallowMissingPlugin(ch.invokeMethod<void>('setStyle', {'tint': tint}));
    }
  }

  void _syncBrightness() {
    final ch = _channel;
    if (ch == null) return;
    final dark = _isDark;
    final tint = _resolveArgb(_effectiveColor, context);
    if (_lastIsDark != dark) {
      _lastIsDark = dark;
      _swallowMissingPlugin(ch.invokeMethod<void>('setBrightness', {'isDark': dark}));
    }
    if (_lastTint != tint) {
      _lastTint = tint;
      _swallowMissingPlugin(ch.invokeMethod<void>('setStyle', {'tint': tint}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.height * (51.0 / 31.0);
    final hidden = maybeHiddenPlaceholder(height: widget.height, width: width);
    if (hidden != null) {
      _channel?.setMethodCallHandler(null);
      _channel = null;
      return hidden;
    }

    return wrapWithModalInteractionGuard(
      ClipRect(
        child: SizedBox(
          height: widget.height,
          width: width,
          child: UiKitView(
            viewType: _viewType,
            creationParamsCodec: const StandardMessageCodec(),
            creationParams: <String, Object?>{
              'value': widget.value,
              'enabled': widget.enabled,
              'isDark': _isDark,
              if (widget.semanticLabel != null) 'semanticLabel': widget.semanticLabel,
              'style': {'tint': _resolveArgb(_effectiveColor, context)},
            },
            onPlatformViewCreated: _onPlatformViewCreated,
            gestureRecognizers: const {
              Factory<HorizontalDragGestureRecognizer>(
                HorizontalDragGestureRecognizer.new,
              ),
              Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
            },
          ),
        ),
      ),
    );
  }
}

/// Direct UIKit `UISegmentedControl` platform view for pre-iOS 26 devices.
class IosDirectNativeSegmentedControl extends StatefulWidget {
  const IosDirectNativeSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.shrinkWrap = false,
    this.height = 36.0,
    this.color,
    this.autoHideOnModal = true,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onValueChanged;
  final bool enabled;
  final bool shrinkWrap;
  final double height;
  final Color? color;
  final bool autoHideOnModal;

  @override
  State<IosDirectNativeSegmentedControl> createState() =>
      _IosDirectNativeSegmentedControlState();
}

class _IosDirectNativeSegmentedControlState
    extends State<IosDirectNativeSegmentedControl>
    with ModalHideMixin<IosDirectNativeSegmentedControl> {
  static const _viewType = 'CupertinoNativeSegmentedControl';

  MethodChannel? _channel;
  int? _lastSelected;
  bool? _lastEnabled;
  bool? _lastIsDark;
  int? _lastTint;
  double? _intrinsicWidth;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _effectiveColor =>
      widget.color ?? Theme.of(context).colorScheme.primary;

  @override
  bool get autoHideOnModal => widget.autoHideOnModal;

  @override
  MethodChannel? get platformViewChannel => _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IosDirectNativeSegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncProps();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightness();
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('${_viewType}_$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'valueChanged') {
        final args = call.arguments as Map<Object?, Object?>?;
        final idx = (args?['index'] as num?)?.toInt();
        if (idx != null) {
          _lastSelected = idx;
          if (idx != widget.selectedIndex) {
            widget.onValueChanged(idx);
          }
        }
      }
      return null;
    });
    _lastSelected = widget.selectedIndex;
    _lastEnabled = widget.enabled;
    _lastIsDark = _isDark;
    _lastTint = _resolveArgb(_effectiveColor, context);
    if (widget.shrinkWrap) {
      unawaited(_measureIntrinsicWidth(channel));
    }
  }

  Future<void> _measureIntrinsicWidth(MethodChannel channel) async {
    try {
      final size = await channel.invokeMapMethod<String, num>('getIntrinsicSize');
      final width = size?['width']?.toDouble();
      if (mounted && _channel == channel && width != null && width.isFinite && width > 0) {
        setState(() => _intrinsicWidth = width);
      }
    } on MissingPluginException {
      // Ignored in tests.
    }
  }

  void _syncProps() {
    final ch = _channel;
    if (ch == null) return;
    final tint = _resolveArgb(_effectiveColor, context);
    if (_lastEnabled != widget.enabled) {
      _lastEnabled = widget.enabled;
      _swallowMissingPlugin(ch.invokeMethod<void>('setEnabled', {'enabled': widget.enabled}));
    }
    if (_lastSelected != widget.selectedIndex) {
      _lastSelected = widget.selectedIndex;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setSelectedIndex', {'index': widget.selectedIndex}),
      );
    }
    if (_lastTint != tint) {
      _lastTint = tint;
      _swallowMissingPlugin(ch.invokeMethod<void>('setStyle', {'tint': tint}));
    }
  }

  void _syncBrightness() {
    final ch = _channel;
    if (ch == null) return;
    final dark = _isDark;
    final tint = _resolveArgb(_effectiveColor, context);
    if (_lastIsDark != dark) {
      _lastIsDark = dark;
      _swallowMissingPlugin(ch.invokeMethod<void>('setBrightness', {'isDark': dark}));
    }
    if (_lastTint != tint) {
      _lastTint = tint;
      _swallowMissingPlugin(ch.invokeMethod<void>('setStyle', {'tint': tint}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = maybeHiddenPlaceholder(
      height: widget.height,
      width: widget.shrinkWrap ? _intrinsicWidth : double.infinity,
    );
    if (hidden != null) {
      _channel?.setMethodCallHandler(null);
      _channel = null;
      return hidden;
    }

    final view = UiKitView(
      key: ValueKey('ios_seg_${widget.labels.join('\u0000')}'),
      viewType: _viewType,
      creationParamsCodec: const StandardMessageCodec(),
      creationParams: <String, Object?>{
        'labels': widget.labels,
        'selectedIndex': widget.selectedIndex.clamp(0, widget.labels.length - 1),
        'enabled': widget.enabled,
        'isDark': _isDark,
        'style': {'tint': _resolveArgb(_effectiveColor, context)},
      },
      onPlatformViewCreated: _onPlatformViewCreated,
      gestureRecognizers: const {
        Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
      },
    );

    if (widget.shrinkWrap) {
      return wrapWithModalInteractionGuard(
        Center(
          child: ClipRect(
            child: SizedBox(
              height: widget.height,
              width: _intrinsicWidth,
              child: view,
            ),
          ),
        ),
      );
    }

    return wrapWithModalInteractionGuard(
      ClipRect(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: view,
        ),
      ),
    );
  }
}

/// Direct UIKit `UISlider` platform view for pre-iOS 26 devices.
class IosDirectNativeSlider extends StatefulWidget {
  const IosDirectNativeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.step,
    this.enabled = true,
    this.height = 44.0,
    this.color,
    this.semanticLabel,
    this.autoHideOnModal = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double? step;
  final bool enabled;
  final double height;
  final Color? color;
  final String? semanticLabel;
  final bool autoHideOnModal;

  @override
  State<IosDirectNativeSlider> createState() => _IosDirectNativeSliderState();
}

class _IosDirectNativeSliderState extends State<IosDirectNativeSlider>
    with ModalHideMixin<IosDirectNativeSlider> {
  static const _viewType = 'CupertinoNativeSlider';

  MethodChannel? _channel;
  double? _lastValue;
  double? _lastMin;
  double? _lastMax;
  double? _lastStep;
  bool? _lastEnabled;
  String? _lastSemanticLabel;
  bool? _lastIsDark;
  int? _lastTint;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _effectiveColor =>
      widget.color ?? Theme.of(context).colorScheme.primary;

  @override
  bool get autoHideOnModal => widget.autoHideOnModal;

  @override
  MethodChannel? get platformViewChannel => _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IosDirectNativeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncProps();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightness();
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('${_viewType}_$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'valueChanged') {
        final args = call.arguments as Map<Object?, Object?>?;
        final next = (args?['value'] as num?)?.toDouble();
        if (next != null) {
          _lastValue = next;
          widget.onChanged(next);
        }
      }
      return null;
    });
    _lastValue = widget.value;
    _lastMin = widget.min;
    _lastMax = widget.max;
    _lastStep = widget.step;
    _lastEnabled = widget.enabled;
    _lastSemanticLabel = widget.semanticLabel;
    _lastIsDark = _isDark;
    _lastTint = _resolveArgb(_effectiveColor, context);
  }

  void _syncProps() {
    final ch = _channel;
    if (ch == null) return;
    final tint = _resolveArgb(_effectiveColor, context);
    if (_lastMin != widget.min || _lastMax != widget.max) {
      _lastMin = widget.min;
      _lastMax = widget.max;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setRange', {'min': widget.min, 'max': widget.max}),
      );
    }
    if (_lastStep != widget.step && widget.step != null) {
      _lastStep = widget.step;
      _swallowMissingPlugin(ch.invokeMethod<void>('setStep', {'step': widget.step}));
    }
    if (_lastEnabled != widget.enabled) {
      _lastEnabled = widget.enabled;
      _swallowMissingPlugin(ch.invokeMethod<void>('setEnabled', {'enabled': widget.enabled}));
    }
    if (_lastSemanticLabel != widget.semanticLabel) {
      _lastSemanticLabel = widget.semanticLabel;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setSemanticLabel', {'label': widget.semanticLabel}),
      );
    }
    final clamped = widget.value.clamp(widget.min, widget.max).toDouble();
    if (_lastValue != clamped) {
      _lastValue = clamped;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setValue', {'value': clamped, 'animated': false}),
      );
    }
    if (_lastTint != tint) {
      _lastTint = tint;
      _swallowMissingPlugin(ch.invokeMethod<void>('setStyle', {'trackTint': tint, 'thumbTint': tint}));
    }
  }

  void _syncBrightness() {
    final ch = _channel;
    if (ch == null) return;
    final dark = _isDark;
    if (_lastIsDark != dark) {
      _lastIsDark = dark;
      _swallowMissingPlugin(ch.invokeMethod<void>('setBrightness', {'isDark': dark}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = maybeHiddenPlaceholder(height: widget.height, width: double.infinity);
    if (hidden != null) {
      _channel?.setMethodCallHandler(null);
      _channel = null;
      return hidden;
    }

    final tint = _resolveArgb(_effectiveColor, context);
    return wrapWithModalInteractionGuard(
      ClipRect(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: UiKitView(
            viewType: _viewType,
            creationParamsCodec: const StandardMessageCodec(),
            creationParams: <String, Object?>{
              'min': widget.min,
              'max': widget.max,
              'value': widget.value.clamp(widget.min, widget.max).toDouble(),
              if (widget.step != null) 'step': widget.step,
              'enabled': widget.enabled,
              'isDark': _isDark,
              if (widget.semanticLabel != null) 'semanticLabel': widget.semanticLabel,
              'style': {'trackTint': tint, 'thumbTint': tint},
            },
            onPlatformViewCreated: _onPlatformViewCreated,
            gestureRecognizers: const {
              Factory<HorizontalDragGestureRecognizer>(
                HorizontalDragGestureRecognizer.new,
              ),
              Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
            },
          ),
        ),
      ),
    );
  }
}
