import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../utils/platform.dart';

Future<String?> showAdaptiveTextInputDialog({
  required BuildContext context,
  required String title,
  required String fieldLabel,
  required String confirmLabel,
  String? message,
  String? hintText,
  String initialValue = '',
  bool obscureText = false,
  String? confirmationFieldLabel,
  String mismatchMessage = 'Values do not match',
  bool trimResult = false,
  bool allowEmpty = false,
}) {
  if (isIos()) {
    return showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => _AdaptiveTextInputDialog(
        title: title,
        message: message,
        fieldLabel: fieldLabel,
        hintText: hintText,
        confirmLabel: confirmLabel,
        obscureText: obscureText,
        confirmationFieldLabel: confirmationFieldLabel,
        mismatchMessage: mismatchMessage,
        trimResult: trimResult,
        allowEmpty: allowEmpty,
        initialValue: initialValue,
        usesCupertinoStyle: true,
      ),
    );
  }

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _AdaptiveTextInputDialog(
      title: title,
      message: message,
      fieldLabel: fieldLabel,
      hintText: hintText,
      confirmLabel: confirmLabel,
      obscureText: obscureText,
      confirmationFieldLabel: confirmationFieldLabel,
      mismatchMessage: mismatchMessage,
      trimResult: trimResult,
      allowEmpty: allowEmpty,
      initialValue: initialValue,
      usesCupertinoStyle: false,
    ),
  );
}

class _AdaptiveTextInputDialog extends StatefulWidget {
  const _AdaptiveTextInputDialog({
    required this.title,
    required this.message,
    required this.fieldLabel,
    required this.hintText,
    required this.confirmLabel,
    required this.obscureText,
    required this.confirmationFieldLabel,
    required this.mismatchMessage,
    required this.trimResult,
    required this.allowEmpty,
    required this.initialValue,
    required this.usesCupertinoStyle,
  });

  final String title;
  final String? message;
  final String fieldLabel;
  final String? hintText;
  final String confirmLabel;
  final bool obscureText;
  final String? confirmationFieldLabel;
  final String mismatchMessage;
  final bool trimResult;
  final bool allowEmpty;
  final String initialValue;
  final bool usesCupertinoStyle;

  @override
  State<_AdaptiveTextInputDialog> createState() =>
      _AdaptiveTextInputDialogState();
}

class _AdaptiveTextInputDialogState extends State<_AdaptiveTextInputDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _confirmationController;
  final FocusNode _confirmationFocusNode = FocusNode();
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
    _controller = TextEditingController(text: widget.initialValue);
    _confirmationController = TextEditingController();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _confirmationController.dispose();
    _confirmationFocusNode.dispose();
    super.dispose();
  }

  bool get _needsConfirmation => widget.confirmationFieldLabel != null;

  bool get _valuesMatch =>
      !_needsConfirmation || _controller.text == _confirmationController.text;

  bool get _hasContent => widget.trimResult
      ? _controller.text.trim().isNotEmpty
      : _controller.text.isNotEmpty;

  bool get _canSubmit => (widget.allowEmpty || _hasContent) && _valuesMatch;

  String get _result =>
      widget.trimResult ? _controller.text.trim() : _controller.text;

  void _close([String? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (isIos()) {
      unawaited(_hideIosKeyboard());
    }
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _hideIosKeyboard() async {
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } on MissingPluginException {
      // Widget tests and non-engine hosts may not expose the text input channel.
    } on PlatformException {
      // Dismissing the dialog must not depend on keyboard channel availability.
    }
  }

  void _onChanged(String value) => setState(() {});

  void _submit() {
    if (_canSubmit) _close(_result);
  }

  Widget _buildFields() {
    final mismatch = _confirmationController.text.isNotEmpty && !_valuesMatch;
    final fields = <Widget>[
      if (widget.message != null) ...[
        Text(widget.message!),
        const SizedBox(height: 12),
      ],
      _buildTextField(
        controller: _controller,
        label: widget.fieldLabel,
        hint: widget.hintText,
        autofocus: true,
        isNext: _needsConfirmation,
        onSubmitted: _needsConfirmation
            ? (_) => _confirmationFocusNode.requestFocus()
            : (_) => _submit(),
      ),
      if (_needsConfirmation) ...[
        const SizedBox(height: 12),
        _buildTextField(
          controller: _confirmationController,
          focusNode: _confirmationFocusNode,
          label: widget.confirmationFieldLabel!,
          isNext: false,
          onSubmitted: (_) => _submit(),
        ),
      ],
      if (mismatch) ...[
        const SizedBox(height: 8),
        Text(
          widget.mismatchMessage,
          style: TextStyle(
            color: widget.usesCupertinoStyle
                ? CupertinoColors.systemRed.resolveFrom(context)
                : Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    FocusNode? focusNode,
    String? hint,
    bool autofocus = false,
    bool isNext = false,
    ValueChanged<String>? onSubmitted,
  }) {
    final action = isNext ? TextInputAction.next : TextInputAction.done;
    if (widget.usesCupertinoStyle) {
      return CupertinoTextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: _obscured,
        autofocus: autofocus,
        placeholder: hint == null ? label : '$label - $hint',
        textInputAction: action,
        suffix: widget.obscureText
            ? Semantics(
                button: true,
                label: _obscured ? '显示密码' : '隐藏密码',
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size.square(32),
                  onPressed: () => setState(() => _obscured = !_obscured),
                  child: Icon(
                    _obscured ? TpIcons.eye : TpIcons.eyeOff,
                    size: TpTokens.iconS,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              )
            : null,
        onChanged: _onChanged,
        onSubmitted: onSubmitted,
      );
    }

    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: _obscured,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: widget.obscureText
            ? IconButton(
                tooltip: _obscured ? '显示密码' : '隐藏密码',
                icon: Icon(
                  _obscured ? TpIcons.eye : TpIcons.eyeOff,
                  size: TpTokens.iconS,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
      ),
      textInputAction: action,
      onChanged: _onChanged,
      onSubmitted: onSubmitted,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.usesCupertinoStyle) {
      return CupertinoAlertDialog(
        title: Text(widget.title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _buildFields(),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: _close,
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: _canSubmit ? _submit : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      );
    }

    final colors = context.tpColors;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(child: _buildFields()),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
          onPressed: _close,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
