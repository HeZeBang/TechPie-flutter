import 'dart:async';
import 'dart:math' as math;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:cupertino_native_better/utils/modal_hide_mixin.dart';
import 'package:flutter/cupertino.dart' show CupertinoDynamicColor, CupertinoTheme;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/platform.dart';

class IosNativeSelectOption {
  const IosNativeSelectOption({
    required this.value,
    required this.label,
    this.sfSymbol,
    this.sfSymbolColor,
  });

  final String value;
  final String label;
  final String? sfSymbol;
  final Color? sfSymbolColor;
}

class IosNativeSelect extends StatelessWidget {
  const IosNativeSelect({
    super.key,
    required this.options,
    required this.onChanged,
    required this.placeholder,
    required this.accessibilityLabel,
    this.value,
    this.shrinkWrap = false,
    this.buttonStyle = CNButtonStyle.glass,
    this.tint,
  });

  final List<IosNativeSelectOption> options;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final String accessibilityLabel;
  final String? value;

  /// Size the button to its label instead of the width it is given.
  final bool shrinkWrap;
  final CNButtonStyle buttonStyle;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((option) => option.value == value).firstOrNull;
    final title = selected?.label ?? placeholder;
    final buttonTint = tint ?? Theme.of(context).colorScheme.onSurface;
    if (usesIosLiquidGlass() && shrinkWrap && buttonStyle == CNButtonStyle.plain) {
      return IgnorePointer(
        ignoring: options.isEmpty,
        child: _InlinePopupMenu(
          title: title,
          accessibilityLabel: accessibilityLabel,
          tint: CupertinoDynamicColor.resolve(buttonTint, context).toARGB32(),
          isDark: ThemeHelper.isDark(context),
          items: [
            for (final option in options)
              (
                label: option.label,
                symbol: option.sfSymbol ?? '',
                color: option.sfSymbolColor == null
                    ? null
                    : CupertinoDynamicColor.resolve(option.sfSymbolColor!, context).toARGB32(),
                checked: option.value == value,
              ),
          ],
          onSelected: _select,
        ),
      );
    }
    return IgnorePointer(
      ignoring: options.isEmpty,
      child: CNPopupMenuButton(
        buttonLabel: title,
        semanticLabel: accessibilityLabel,
        height: 44,
        shrinkWrap: shrinkWrap,
        // UIMenu otherwise reverses its items when it opens upwards, so the
        // same list would read in two orders depending on where it sits.
        preserveTopToBottomOrder: true,
        buttonStyle: buttonStyle,
        tint: buttonTint,
        items: [
          for (final option in options)
            CNPopupMenuItem(
              label: option.label,
              // Match UIMenu's default size on both creation and updates.
              icon: option.sfSymbol == null
                  ? null
                  : CNSymbol(
                      option.sfSymbol!,
                      size: 0,
                      color: option.sfSymbolColor,
                    ),
              checked: option.value == value,
            ),
        ],
        onSelected: _select,
      ),
    );
  }

  void _select(int index) {
    if (index >= 0 && index < options.length) onChanged(options[index].value);
  }
}

typedef _InlineMenuItem = ({String label, String symbol, int? color, bool checked});

// Use the plugin's UIKit menu, with a platform view identity independent of
// the current label and tint. The pinned plugin already supports in-place
// updates for both through its per-view channel.
class _InlinePopupMenu extends StatefulWidget {
  const _InlinePopupMenu({
    required this.title,
    required this.accessibilityLabel,
    required this.tint,
    required this.isDark,
    required this.items,
    required this.onSelected,
  });

  final String title;
  final String accessibilityLabel;
  final int tint;
  final bool isDark;
  final List<_InlineMenuItem> items;
  final ValueChanged<int> onSelected;

  @override
  State<_InlinePopupMenu> createState() => _InlinePopupMenuState();
}

class _InlinePopupMenuState extends State<_InlinePopupMenu> with ModalHideMixin<_InlinePopupMenu> {
  static const _viewType = 'CupertinoNativePopupMenuButton';

  MethodChannel? _channel;
  double _width = 80;

  @override
  bool get autoHideOnModal => true;

  @override
  MethodChannel? get platformViewChannel => _channel;

  Map<String, Object> get _menuItems => {
        'labels': [for (final item in widget.items) item.label],
        'sfSymbols': [for (final item in widget.items) item.symbol],
        'checked': [for (final item in widget.items) item.checked],
        'sfSymbolColors': [for (final item in widget.items) item.color],
      };

  @override
  void didUpdateWidget(covariant _InlinePopupMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNative(oldWidget);
  }

  void _syncNative([_InlinePopupMenu? previous]) {
    final channel = _channel;
    if (channel == null) return;
    if (widget.isDark != previous?.isDark) {
      unawaited(channel.invokeMethod<void>('setBrightness', {'isDark': widget.isDark}));
    }
    if (widget.tint != previous?.tint) {
      unawaited(channel.invokeMethod<void>('setStyle', {'tint': widget.tint}));
    }
    if (widget.title != previous?.title) {
      unawaited(_updateTitle(channel, widget.title));
    }
    if (widget.accessibilityLabel != previous?.accessibilityLabel) {
      unawaited(
        channel.invokeMethod<void>('setSemanticLabel', {'label': widget.accessibilityLabel}),
      );
    }
    if (!listEquals(widget.items, previous?.items)) {
      unawaited(channel.invokeMethod<void>('setItems', _menuItems));
    }
  }

  Future<void> _updateTitle(MethodChannel channel, String title) async {
    await channel.invokeMethod<void>('setButtonTitle', {'title': title});
    final size = await channel.invokeMapMethod<String, num>('getIntrinsicSize');
    final width = size?['width']?.toDouble();
    if (mounted &&
        _channel == channel &&
        widget.title == title &&
        width != null &&
        width.isFinite &&
        width > 0 &&
        width != _width) {
      setState(() => _width = width);
    }
  }

  void _onCreated(int id) {
    _detachChannel();
    final channel = MethodChannel('${_viewType}_$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'itemSelected') {
        final index = (call.arguments as Map<Object?, Object?>?)?['index'] as int?;
        if (index != null) widget.onSelected(index);
      }
    });
    // The selection may have changed while UIKit was creating the view.
    _syncNative();
  }

  void _detachChannel() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
  }

  @override
  void dispose() {
    _detachChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const height = iosMinimumInteractiveDimension;
    // UIButton can measure a longer title against the previous, narrower
    // bounds and return a wrapped size. Reserve one line as it changes.
    final title = TextPainter(
      text: TextSpan(
        text: widget.title,
        style: CupertinoTheme.of(context).textTheme.actionTextStyle,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = math.max(_width, title.width.ceilToDouble() + 28);
    title.dispose();
    final placeholder = maybeHiddenPlaceholder(height: height, width: width);
    if (placeholder != null) {
      _detachChannel();
      return placeholder;
    }
    return ClipRect(
      child: SizedBox(
        height: height,
        width: width,
        child: UiKitView(
          viewType: _viewType,
          creationParams: {
            'buttonTitle': widget.title,
            'semanticLabel': widget.accessibilityLabel,
            'buttonStyle': 'plain',
            'isDark': widget.isDark,
            'style': {'tint': widget.tint},
            'preserveTopToBottomOrder': true,
            ..._menuItems,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onCreated,
          gestureRecognizers: const {
            Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
          },
        ),
      ),
    );
  }
}
