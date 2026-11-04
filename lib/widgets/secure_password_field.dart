import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';

/// A secure text input that never briefly paints the last typed character.
class SecurePasswordField extends StatefulWidget {
  const SecurePasswordField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.decoration,
    this.enabled = true,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String placeholder;
  final InputDecoration? decoration;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SecurePasswordField> createState() => _SecurePasswordFieldState();
}

class _SecurePasswordFieldState extends State<SecurePasswordField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  final _focus = FocusNode();
  final _editableKey = GlobalKey<EditableTextState>();
  late final _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _showSelectionHandles = false;

  @override
  GlobalKey<EditableTextState> get editableTextKey => _editableKey;
  @override
  bool get forcePressEnabled => false;
  @override
  bool get selectionEnabled => widget.enabled;

  void _selectionChanged(TextSelection selection, SelectionChangedCause? cause) {
    final show = widget.enabled &&
        cause != SelectionChangedCause.keyboard &&
        (cause == SelectionChangedCause.longPress || widget.controller.text.isNotEmpty);
    if (_showSelectionHandles != show) setState(() => _showSelectionHandles = show);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([widget.controller, _focus]),
        builder: (context, _) {
          final theme = Theme.of(context);
          final cupertino = isIos() && widget.decoration == null;
          final style = theme.textTheme.titleMedium!.copyWith(
            fontSize: cupertino ? 17 : 16,
            color: theme.colorScheme.onSurface,
          );
          final editable = _MaskedEditableText(
            key: _editableKey,
            controller: widget.controller,
            focusNode: _focus,
            style: style,
            cursorColor: theme.colorScheme.primary,
            backgroundCursorColor: CupertinoColors.inactiveGray,
            readOnly: !widget.enabled,
            keyboardAppearance: theme.brightness,
            showSelectionHandles: _showSelectionHandles,
            onSelectionChanged: _selectionChanged,
            selectionColor: TextSelectionTheme.of(context).selectionColor ??
                theme.colorScheme.primary.withValues(alpha: 0.3),
            textInputAction: widget.textInputAction,
            selectionControls: isIos()
                ? cupertinoTextSelectionHandleControls
                : materialTextSelectionHandleControls,
            contextMenuBuilder: (context, state) =>
                AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
            onSubmitted: widget.onSubmitted,
          );
          final field = cupertino
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      if (widget.controller.text.isEmpty)
                        Text(
                          widget.placeholder,
                          style: style.copyWith(
                            color: CupertinoColors.placeholderText.resolveFrom(context),
                          ),
                        ),
                      editable,
                    ],
                  ),
                )
              : InputDecorator(
                  decoration: (widget.decoration ?? InputDecoration(hintText: widget.placeholder))
                      .copyWith(enabled: widget.enabled),
                  isFocused: _focus.hasFocus,
                  isEmpty: widget.controller.text.isEmpty,
                  child: editable,
                );
          return Semantics(
            label: cupertino ? widget.placeholder : null,
            child: _gestures.buildGestureDetector(
              behavior: HitTestBehavior.translucent,
              child: field,
            ),
          );
        },
      );
}

class _MaskedEditableText extends EditableText {
  _MaskedEditableText({
    super.key,
    required super.controller,
    required super.focusNode,
    required super.style,
    required super.cursorColor,
    required super.backgroundCursorColor,
    required super.readOnly,
    required super.keyboardAppearance,
    required super.showSelectionHandles,
    required super.onSelectionChanged,
    required super.selectionColor,
    required super.textInputAction,
    required super.selectionControls,
    required super.contextMenuBuilder,
    required super.onSubmitted,
  }) : super(
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          autofillHints: null,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          keyboardType: TextInputType.visiblePassword,
          rendererIgnoresPointer: true,
        );

  @override
  EditableTextState createState() => _MaskedEditableTextState();
}

class _MaskedEditableTextState extends EditableTextState {
  @override
  TextSpan buildTextSpan() => TextSpan(
        style: widget.style,
        text: widget.obscuringCharacter * widget.controller.text.length,
      );
}
