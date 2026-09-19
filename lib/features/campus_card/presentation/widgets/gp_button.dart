import 'package:flutter/material.dart';

import '../../../../utils/adaptive_motion.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';

enum GpButtonVariant { primary, secondary, tertiary, destructive }

final class GpButton extends StatelessWidget {
  const GpButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = GpButtonVariant.primary,
    this.loading = false,
    this.reason,
    this.fullWidth = true,
    this.reasonKey,
    this.labelKey,
  });

  final String label;
  final VoidCallback? onPressed;
  final GpButtonVariant variant;
  final bool loading;
  final String? reason;
  final bool fullWidth;
  final Key? reasonKey;
  final Key? labelKey;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final c = context.gpColors;
    final enabled = _enabled;
    final fg = switch (variant) {
      GpButtonVariant.primary || GpButtonVariant.destructive => c.onAction,
      _ => enabled ? c.action : c.textDisabled,
    };
    final bg = switch (variant) {
      GpButtonVariant.primary => enabled ? c.action : c.surfaceDisabled,
      GpButtonVariant.destructive => enabled ? c.danger : c.surfaceDisabled,
      GpButtonVariant.secondary =>
        enabled ? Colors.transparent : c.surfaceDisabled,
      GpButtonVariant.tertiary => Colors.transparent,
    };
    final border = switch (variant) {
      GpButtonVariant.secondary => Border.all(
          color: enabled ? c.action : c.borderStrong,
        ),
      _ => null,
    };

    final key = labelKey;
    Widget content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: GpTokens.minTouchTarget),
      child: Center(
        widthFactor: fullWidth ? null : 1,
        heightFactor: 1,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                key: key,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                    ),
              ),
      ),
    );
    content = Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(
        horizontal: GpTokens.space4,
        vertical: 0,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(GpTokens.radiusM),
        border: border,
      ),
      child: content,
    );

    if (reason != null && onPressed == null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          const SizedBox(height: GpTokens.space1),
          Text(
            reason!,
            key: reasonKey,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.textDisabled),
          ),
        ],
      );
    }

    final reduce = !appAnimationsEnabled(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(GpTokens.radiusM),
          child: InkWell(
            borderRadius: BorderRadius.circular(GpTokens.radiusM),
            onTap: enabled ? onPressed : null,
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.98,
              duration: reduce ? Duration.zero : Durations.short1,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
