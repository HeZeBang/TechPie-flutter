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
      GpButtonVariant.primary => enabled ? c.onAction : c.textDisabled,
      GpButtonVariant.destructive => enabled ? Colors.white : c.textDisabled,
      _ => enabled ? c.action : c.textDisabled,
    };
    final bg = switch (variant) {
      GpButtonVariant.primary => enabled ? c.action : c.surfaceDisabled,
      GpButtonVariant.destructive => enabled ? c.danger : c.surfaceDisabled,
      GpButtonVariant.secondary =>
        enabled ? Colors.transparent : c.surfaceDisabled,
      GpButtonVariant.tertiary => Colors.transparent,
    };
    final borderSide = switch (variant) {
      GpButtonVariant.secondary => BorderSide(
          color: enabled ? c.action : c.borderStrong,
        ),
      _ => BorderSide.none,
    };
    final isSolid = enabled &&
        (variant == GpButtonVariant.primary ||
            variant == GpButtonVariant.destructive);
    final overlayBase = isSolid ? Colors.white : c.textPrimary;

    final key = labelKey;
    final inner = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: GpTokens.minTouchTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GpTokens.space4),
        child: Center(
          widthFactor: fullWidth ? null : 1,
          heightFactor: 1,
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.action,
                  ),
                )
              : Text(
                  label,
                  key: key,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: fg,
                      ),
                ),
        ),
      ),
    );

    final reduce = !appAnimationsEnabled(context);
    final radius = BorderRadius.circular(GpTokens.radiusM);
    Widget button = SizedBox(
      width: fullWidth ? double.infinity : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.98,
        duration: reduce ? Duration.zero : Durations.short1,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: borderSide,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: radius,
            hoverColor: overlayBase.withValues(alpha: isSolid ? 0.12 : 0.05),
            highlightColor: overlayBase.withValues(alpha: isSolid ? 0.16 : 0.08),
            splashColor: isSolid
                ? Colors.white.withValues(alpha: 0.22)
                : c.actionAlt,
            onTap: enabled ? onPressed : null,
            child: inner,
          ),
        ),
      ),
    );

    if (reason != null && onPressed == null) {
      button = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          button,
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

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(child: button),
    );
  }
}
