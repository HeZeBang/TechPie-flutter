import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/ports/platform_ports.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';

final class SixDigitPasswordPanel extends StatefulWidget {
  const SixDigitPasswordPanel({
    super.key,
    required this.onSubmit,
    required this.onCancel,
    this.feedback,
  });

  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final FeedbackPort? feedback;

  @override
  State<SixDigitPasswordPanel> createState() => _SixDigitPasswordPanelState();
}

class _SixDigitPasswordPanelState extends State<SixDigitPasswordPanel> {
  String _digits = '';
  bool _submitted = false;

  void _press(String value) {
    if (_submitted || _digits.length >= 6) return;
    setState(() => _digits += value);
    if (_digits.length == 6) {
      _submitted = true;
      widget.onSubmit(_digits);
    }
  }

  void _delete() {
    if (_submitted || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '消费密码, ${_digits.length}/6',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Pay',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                tooltip: '取消',
                onPressed: widget.onCancel,
                icon: Icon(GpPlatformIcons.closeCircleFilled(context)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '输入 6 位消费密码',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < 6; index++)
                AnimatedContainer(
                  key: Key('password-dot-$index-${index < _digits.length}'),
                  duration: const Duration(milliseconds: 120),
                  width: 15,
                  height: 15,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < _digits.length
                        ? context.gpColors.textPrimary
                        : context.gpColors.surfaceDisabled,
                    border: Border.all(color: context.gpColors.borderStrong),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            _PasswordRow(
              children: [
                for (final digit in row)
                  _PasswordKey(
                    label: digit,
                    feedback: widget.feedback,
                    onTap: () => _press(digit),
                  ),
              ],
            ),
          _PasswordRow(
            children: [
              const SizedBox(),
              _PasswordKey(
                label: '0',
                feedback: widget.feedback,
                onTap: () => _press('0'),
              ),
              _PasswordKey(
                icon: GpPlatformIcons.backspace(context),
                feedback: widget.feedback,
                onTap: _delete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _PasswordRow extends StatelessWidget {
  const _PasswordRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          for (final child in children)
            Expanded(
              child: Padding(padding: const EdgeInsets.all(3), child: child),
            ),
        ],
      ),
    );
  }
}

final class _PasswordKey extends StatefulWidget {
  const _PasswordKey({
    this.label,
    this.icon,
    required this.onTap,
    this.feedback,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final FeedbackPort? feedback;

  @override
  State<_PasswordKey> createState() => _PasswordKeyState();
}

final class _PasswordKeyState extends State<_PasswordKey> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    if (value) {
      unawaited(widget.feedback?.play(FeedbackEvent.selection));
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalColor =
        widget.label == null ? Colors.transparent : context.gpColors.surface;
    final pressedColor = Color.alphaBlend(
      context.gpColors.textPrimary.withValues(alpha: 0.14),
      context.gpColors.surface,
    );
    final identifier = widget.label ?? 'delete';
    return Listener(
      key: Key('password-key-$identifier'),
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapCancel: () => _setPressed(false),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            key: Key('password-key-$identifier-surface'),
            color: _pressed ? pressedColor : normalColor,
            child: Center(
              child: widget.icon == null
                  ? Text(
                      widget.label!,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : Icon(widget.icon, size: 23),
            ),
          ),
        ),
      ),
    );
  }
}
