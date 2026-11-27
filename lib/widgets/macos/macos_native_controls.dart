import 'dart:async';

import 'package:cupertino_native_better/utils/modal_hide_mixin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Item entry for [MacosNativePopUpButton] and [MacosNativeUi.showContextMenu].
@immutable
class MacosPopUpItem {
  const MacosPopUpItem({
    required this.label,
    this.sfSymbol,
    this.enabled = true,
    this.checked = false,
    this.isDestructive = false,
    this.isDivider = false,
  });

  const MacosPopUpItem.divider()
      : label = '',
        sfSymbol = null,
        enabled = false,
        checked = false,
        isDestructive = false,
        isDivider = true;

  final String label;
  final String? sfSymbol;
  final bool enabled;
  final bool checked;
  final bool isDestructive;
  final bool isDivider;

  Map<String, Object?> toMap() => <String, Object?>{
        'label': label,
        if (sfSymbol != null) 'sfSymbol': sfSymbol,
        'enabled': enabled,
        'checked': checked,
        'isDestructive': isDestructive,
        'isDivider': isDivider,
      };
}

/// Modal dialog and context menu bridge backed by native AppKit (`NSAlert` and
/// `NSMenu`) in `MacosNativeControlsPlugin.swift`.
abstract final class MacosNativeUi {
  static const MethodChannel _channel = MethodChannel('techpie/macos_native_ui');

  /// Presents a native macOS `NSAlert` sheet attached to the active window.
  ///
  /// Throws [MissingPluginException] when the macOS plugin is not registered
  /// (e.g., pure Dart VM widget tests) so callers can cleanly fall back.
  static Future<int?> showAlert({
    required String title,
    required String message,
    required List<Map<String, Object?>> actions,
  }) async {
    final reply = await _channel.invokeMapMethod<String, Object?>(
      'showAlert',
      <String, Object?>{
        'title': title,
        'message': message,
        'actions': actions,
      },
    );
    if (reply == null) return null;
    return (reply['index'] as num?)?.toInt();
  }

  /// Presents a native macOS `NSMenu` popup at window global coordinates.
  ///
  /// Throws [MissingPluginException] when the macOS plugin is not registered
  /// so callers can fall back to Flutter's `showMenu`.
  static Future<int?> showContextMenu({
    required Offset globalPosition,
    required List<MacosPopUpItem> items,
    required bool isDark,
  }) {
    return _channel.invokeMethod<int>(
      'showContextMenu',
      <String, Object?>{
        'x': globalPosition.dx,
        'y': globalPosition.dy,
        'isDark': isDark,
        'items': [for (final item in items) item.toMap()],
      },
    );
  }
}

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

/// Native AppKit `NSSwitch` embedded via `AppKitView`.
class MacosNativeSwitch extends StatefulWidget {
  const MacosNativeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
    this.autoHideOnModal = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? semanticLabel;
  final bool autoHideOnModal;

  @override
  State<MacosNativeSwitch> createState() => _MacosNativeSwitchState();
}

class _MacosNativeSwitchState extends State<MacosNativeSwitch>
    with ModalHideMixin<MacosNativeSwitch> {
  static const _viewType = 'TechPieMacSwitch';
  static const double _width = 40.0;
  static const double _height = 24.0;

  MethodChannel? _channel;
  bool? _lastValue;
  bool? _lastEnabled;
  String? _lastSemanticLabel;
  bool? _lastIsDark;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

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
  void didUpdateWidget(covariant MacosNativeSwitch oldWidget) {
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
  }

  void _syncProps() {
    final ch = _channel;
    if (ch == null) return;
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
      _swallowMissingPlugin(ch.invokeMethod<void>('setValue', {'value': widget.value}));
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
    final hidden = maybeHiddenPlaceholder(height: _height, width: _width);
    if (hidden != null) {
      _channel?.setMethodCallHandler(null);
      _channel = null;
      return hidden;
    }
    return SizedBox(
      width: _width,
      height: _height,
      child: AppKitView(
        viewType: _viewType,
        creationParamsCodec: const StandardMessageCodec(),
        creationParams: <String, Object?>{
          'value': widget.value,
          'enabled': widget.enabled,
          'isDark': _isDark,
          if (widget.semanticLabel != null) 'semanticLabel': widget.semanticLabel,
        },
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: const {
          Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
          Factory<HorizontalDragGestureRecognizer>(
            HorizontalDragGestureRecognizer.new,
          ),
        },
      ),
    );
  }
}

/// Native AppKit `NSSegmentedControl` embedded via `AppKitView`.
class MacosNativeSegmentedControl extends StatefulWidget {
  const MacosNativeSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.shrinkWrap = false,
    this.height = 32.0,
    this.semanticLabel,
    this.autoHideOnModal = true,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onValueChanged;
  final bool enabled;
  final bool shrinkWrap;
  final double height;
  final String? semanticLabel;
  final bool autoHideOnModal;

  @override
  State<MacosNativeSegmentedControl> createState() =>
      _MacosNativeSegmentedControlState();
}

class _MacosNativeSegmentedControlState extends State<MacosNativeSegmentedControl>
    with ModalHideMixin<MacosNativeSegmentedControl> {
  static const _viewType = 'TechPieMacSegmentedControl';

  MethodChannel? _channel;
  List<String>? _lastLabels;
  int? _lastSelected;
  bool? _lastEnabled;
  String? _lastSemanticLabel;
  bool? _lastIsDark;
  double? _intrinsicWidth;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

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
  void didUpdateWidget(covariant MacosNativeSegmentedControl oldWidget) {
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
    _lastLabels = List<String>.of(widget.labels);
    _lastSelected = widget.selectedIndex;
    _lastEnabled = widget.enabled;
    _lastSemanticLabel = widget.semanticLabel;
    _lastIsDark = _isDark;
    unawaited(_measureIntrinsicWidth(channel));
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
    if (!listEquals(_lastLabels, widget.labels)) {
      _lastLabels = List<String>.of(widget.labels);
      _lastSelected = widget.selectedIndex;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setLabels', {
          'labels': widget.labels,
          'selectedIndex': widget.selectedIndex,
        }),
      );
      unawaited(_measureIntrinsicWidth(ch));
    } else if (_lastSelected != widget.selectedIndex) {
      _lastSelected = widget.selectedIndex;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setSelectedIndex', {'index': widget.selectedIndex}),
      );
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
    final double? width = widget.shrinkWrap
        ? (_intrinsicWidth ?? (widget.labels.length * 76.0).clamp(120.0, 420.0))
        : null;
    final hidden = maybeHiddenPlaceholder(
      height: widget.height,
      width: width ?? 160.0,
    );
    if (hidden != null) {
      _channel?.setMethodCallHandler(null);
      _channel = null;
      return hidden;
    }
    return SizedBox(
      height: widget.height,
      width: width,
      child: AppKitView(
        viewType: _viewType,
        creationParamsCodec: const StandardMessageCodec(),
        creationParams: <String, Object?>{
          'labels': widget.labels,
          'selectedIndex': widget.selectedIndex,
          'enabled': widget.enabled,
          'shrinkWrap': widget.shrinkWrap,
          'isDark': _isDark,
          if (widget.semanticLabel != null) 'semanticLabel': widget.semanticLabel,
        },
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: const {
          Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
        },
      ),
    );
  }
}

/// Native AppKit `NSPopUpButton` embedded via `AppKitView` (supports both
/// pop-up pickers and pull-down action menus).
class MacosNativePopUpButton extends StatefulWidget {
  const MacosNativePopUpButton({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.placeholder = '',
    this.enabled = true,
    this.shrinkWrap = false,
    this.height = 34.0,
    this.semanticLabel,
    this.autoHideOnModal = true,
  })  : pullsDown = false,
        borderless = false,
        buttonTitle = null,
        buttonIconName = null;

  const MacosNativePopUpButton.menu({
    super.key,
    required this.items,
    required this.onSelected,
    this.buttonTitle,
    this.buttonIconName,
    this.enabled = true,
    this.shrinkWrap = true,
    this.borderless = false,
    this.height = 32.0,
    this.semanticLabel,
    this.autoHideOnModal = true,
  })  : pullsDown = true,
        selectedIndex = -1,
        placeholder = '';

  final List<MacosPopUpItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String placeholder;
  final bool enabled;
  final bool shrinkWrap;
  final bool pullsDown;
  final bool borderless;
  final String? buttonTitle;
  final String? buttonIconName;
  final double height;
  final String? semanticLabel;
  final bool autoHideOnModal;

  @override
  State<MacosNativePopUpButton> createState() => _MacosNativePopUpButtonState();
}

class _MacosNativePopUpButtonState extends State<MacosNativePopUpButton>
    with ModalHideMixin<MacosNativePopUpButton> {
  static const _viewType = 'TechPieMacPopUpButton';

  MethodChannel? _channel;
  List<Map<String, Object?>> _lastEncodedItems = const [];
  int? _lastSelected;
  bool? _lastEnabled;
  String? _lastTitle;
  String? _lastPlaceholder;
  String? _lastSemanticLabel;
  bool? _lastIsDark;
  double? _intrinsicWidth;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  bool get autoHideOnModal => widget.autoHideOnModal;

  @override
  MethodChannel? get platformViewChannel => _channel;

  List<Map<String, Object?>> _encodeItems() =>
      [for (final item in widget.items) item.toMap()];

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MacosNativePopUpButton oldWidget) {
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
      if (call.method == 'itemSelected') {
        final args = call.arguments as Map<Object?, Object?>?;
        final idx = (args?['index'] as num?)?.toInt();
        if (idx != null) {
          if (!widget.pullsDown) _lastSelected = idx;
          widget.onSelected(idx);
        }
      }
      return null;
    });
    _lastEncodedItems = _encodeItems();
    _lastSelected = widget.selectedIndex;
    _lastEnabled = widget.enabled;
    _lastTitle = widget.buttonTitle;
    _lastPlaceholder = widget.placeholder;
    _lastSemanticLabel = widget.semanticLabel;
    _lastIsDark = _isDark;
    unawaited(_measureIntrinsicWidth(channel));
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

  bool _sameItems(List<Map<String, Object?>> a, List<Map<String, Object?>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!mapEquals(a[i], b[i])) return false;
    }
    return true;
  }

  void _syncProps() {
    final ch = _channel;
    if (ch == null) return;
    final encoded = _encodeItems();
    if (!_sameItems(_lastEncodedItems, encoded) ||
        _lastPlaceholder != widget.placeholder ||
        _lastTitle != widget.buttonTitle) {
      _lastEncodedItems = encoded;
      _lastSelected = widget.selectedIndex;
      _lastPlaceholder = widget.placeholder;
      _lastTitle = widget.buttonTitle;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setItems', {
          'items': encoded,
          'selectedIndex': widget.selectedIndex,
          'placeholder': widget.placeholder,
          if (widget.buttonTitle != null) 'buttonTitle': widget.buttonTitle,
        }),
      );
      unawaited(_measureIntrinsicWidth(ch));
    } else if (_lastSelected != widget.selectedIndex && !widget.pullsDown) {
      _lastSelected = widget.selectedIndex;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setSelectedIndex', {'index': widget.selectedIndex}),
      );
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
    final isIconOnlyMenu = widget.pullsDown &&
        widget.buttonIconName != null &&
        (widget.buttonTitle?.isEmpty ?? true);
    final double? width = isIconOnlyMenu
        ? 34.0
        : widget.shrinkWrap
            ? (_intrinsicWidth ?? 120.0)
            : null;
    final hidden = maybeHiddenPlaceholder(
      height: widget.height,
      width: width ?? 120.0,
    );
    if (hidden != null) {
      _channel?.setMethodCallHandler(null);
      _channel = null;
      return hidden;
    }
    return SizedBox(
      height: widget.height,
      width: width,
      child: AppKitView(
        viewType: _viewType,
        creationParamsCodec: const StandardMessageCodec(),
        creationParams: <String, Object?>{
          'pullsDown': widget.pullsDown,
          'borderless': widget.borderless,
          'items': _encodeItems(),
          'selectedIndex': widget.selectedIndex,
          'placeholder': widget.placeholder,
          if (widget.buttonTitle != null) 'buttonTitle': widget.buttonTitle,
          if (widget.buttonIconName != null) 'buttonIconName': widget.buttonIconName,
          'enabled': widget.enabled,
          'isDark': _isDark,
          if (widget.semanticLabel != null) 'semanticLabel': widget.semanticLabel,
        },
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: const {
          Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
        },
      ),
    );
  }
}

/// Native AppKit `NSSlider` embedded via `AppKitView`.
class MacosNativeSlider extends StatefulWidget {
  const MacosNativeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.step,
    this.enabled = true,
    this.height = 28.0,
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
  final String? semanticLabel;
  final bool autoHideOnModal;

  @override
  State<MacosNativeSlider> createState() => _MacosNativeSliderState();
}

class _MacosNativeSliderState extends State<MacosNativeSlider>
    with ModalHideMixin<MacosNativeSlider> {
  static const _viewType = 'TechPieMacSlider';

  MethodChannel? _channel;
  double? _lastValue;
  double? _lastMin;
  double? _lastMax;
  double? _lastStep;
  bool? _lastEnabled;
  String? _lastSemanticLabel;
  bool? _lastIsDark;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

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
  void didUpdateWidget(covariant MacosNativeSlider oldWidget) {
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
  }

  void _syncProps() {
    final ch = _channel;
    if (ch == null) return;
    if (_lastMin != widget.min || _lastMax != widget.max) {
      _lastMin = widget.min;
      _lastMax = widget.max;
      _swallowMissingPlugin(
        ch.invokeMethod<void>('setRange', {'min': widget.min, 'max': widget.max}),
      );
    }
    if (_lastStep != widget.step) {
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
    if (_lastValue != widget.value) {
      _lastValue = widget.value;
      _swallowMissingPlugin(ch.invokeMethod<void>('setValue', {'value': widget.value}));
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
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AppKitView(
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
        },
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: const {
          Factory<HorizontalDragGestureRecognizer>(
            HorizontalDragGestureRecognizer.new,
          ),
          Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
        },
      ),
    );
  }
}

/// Native AppKit `NSButton` checkbox embedded via `AppKitView`.
class MacosNativeCheckbox extends StatefulWidget {
  const MacosNativeCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
    this.autoHideOnModal = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? semanticLabel;
  final bool autoHideOnModal;

  @override
  State<MacosNativeCheckbox> createState() => _MacosNativeCheckboxState();
}

class _MacosNativeCheckboxState extends State<MacosNativeCheckbox>
    with ModalHideMixin<MacosNativeCheckbox> {
  static const _viewType = 'TechPieMacCheckbox';
  static const double _size = 24.0;

  MethodChannel? _channel;
  bool? _lastValue;
  bool? _lastEnabled;
  String? _lastSemanticLabel;
  bool? _lastIsDark;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

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
  void didUpdateWidget(covariant MacosNativeCheckbox oldWidget) {
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
  }

  void _syncProps() {
    final ch = _channel;
    if (ch == null) return;
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
      _swallowMissingPlugin(ch.invokeMethod<void>('setValue', {'value': widget.value}));
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
    final hidden = maybeHiddenPlaceholder(height: _size, width: _size);
    if (hidden != null) {
      _channel?.setMethodCallHandler(null);
      _channel = null;
      return hidden;
    }
    return SizedBox(
      width: _size,
      height: _size,
      child: AppKitView(
        viewType: _viewType,
        creationParamsCodec: const StandardMessageCodec(),
        creationParams: <String, Object?>{
          'value': widget.value,
          'enabled': widget.enabled,
          'isDark': _isDark,
          if (widget.semanticLabel != null) 'semanticLabel': widget.semanticLabel,
        },
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: const {
          Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
        },
      ),
    );
  }
}
