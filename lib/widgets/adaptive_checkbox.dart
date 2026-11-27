import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/platform.dart';
import 'design_system/tp_list_row.dart';
import 'macos/macos_native_controls.dart';

/// Platform-adaptive checkbox:
/// - macOS: native AppKit `NSButton` checkbox (`MacosNativeCheckbox`)
/// - iOS: Apple HIG circular checkmark control inside a 44pt tap target
/// - Other platforms: Material `Checkbox`
class AdaptiveCheckbox extends StatelessWidget {
  const AdaptiveCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && onChanged != null;

    if (usesMacOsNativeControls()) {
      return MacosNativeCheckbox(
        value: value,
        enabled: interactive,
        semanticLabel: semanticLabel,
        onChanged: (next) => onChanged?.call(next),
      );
    }

    if (isIos()) {
      final colors = context.tpColors;
      final accent = colors.brand;
      return Semantics(
        checked: value,
        enabled: interactive,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? () => onChanged?.call(!value) : null,
          child: SizedBox(
            width: iosMinimumInteractiveDimension,
            height: iosMinimumInteractiveDimension,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? accent : Colors.transparent,
                  border: Border.all(
                    color: value
                        ? accent
                        : colors.textMuted.withValues(alpha: interactive ? 0.65 : 0.35),
                    width: 1.6,
                  ),
                ),
                child: value
                    ? Icon(
                        CupertinoIcons.checkmark_alt,
                        size: 15,
                        color: colors.onBrand,
                      )
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    return Checkbox(
      value: value,
      onChanged: interactive ? onChanged : null,
    );
  }
}

/// Platform-adaptive checkbox row built on [TpListRow] + [AdaptiveCheckbox].
class AdaptiveCheckboxRow extends StatelessWidget {
  const AdaptiveCheckboxRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.trailing,
    this.enabled = true,
    this.showDivider = false,
    this.subtitleMaxLines = 2,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final bool enabled;
  final bool showDivider;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && onChanged != null;
    return TpListRow(
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: subtitleMaxLines,
      leading: AdaptiveCheckbox(
        value: value,
        enabled: interactive,
        semanticLabel: title,
        onChanged: onChanged,
      ),
      trailing: trailing,
      showDivider: showDivider,
      onTap: interactive ? () => onChanged?.call(!value) : null,
    );
  }
}
