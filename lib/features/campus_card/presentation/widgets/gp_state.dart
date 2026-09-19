import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';
import '../../core/errors/core_error_catalog.dart';
import '../icons/geekpay_icons.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import 'gp_button.dart';

/// Static skeleton block (no shimmer per Part A §8).
final class GpSkeleton extends StatelessWidget {
  const GpSkeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = GpTokens.radiusS,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: context.gpColors.surfaceDisabled,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: context.gpColors.border),
      ),
    );
  }
}

/// Unified 4-state banner family per B1 §20.
final class GpStateView extends StatelessWidget {
  const GpStateView({
    super.key,
    this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.isError = false,
    this.centered = false,
    this.titleStyle,
  });

  final GpIconGeometry? icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;
  final bool centered;
  final TextStyle? titleStyle;

  factory GpStateView.error(Object error, {VoidCallback? onRetry}) =>
      GpStateView(
        title: errorIsNetwork(error) ? '网络异常，请重试' : safeUiError(error),
        actionLabel: '重试',
        onAction: onRetry,
        isError: true,
      );

  static bool errorIsNetwork(Object error) {
    if (error is AppFailure) {
      return error.kind == FailureKind.network ||
          error.kind == FailureKind.timeout;
    }
    final s = error.toString();
    return s.contains('SocketException') ||
        s.contains('TimeoutException') ||
        s.contains('DioException');
  }

  /// Returns ONLY the failure's self-declared safe text: AppFailure renders
  /// [AppFailure.safeMessage]; anything else collapses to a generic string.
  /// Never touches cause, code, raw exception payloads, or request fields —
  /// AppFailure's own toString is intentionally safeMessage-free.
  static String safeUiError(Object error) {
    if (error is AppFailure) {
      return CoreErrorCatalog.resolve(error.safeMessage);
    }
    return '发生未知错误';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.gpColors;
    final body = Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              GpIcon(
                icon!,
                size: 28,
                color: isError ? c.danger : c.textSecondary,
              ),
              const SizedBox(width: GpTokens.space3),
            ],
            Expanded(
              child: MergeSemantics(
                child: Text(
                  title,
                  style: titleStyle ??
                      (isError
                          ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: c.textSecondary,
                              )
                          : Theme.of(context).textTheme.headlineSmall),
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                ),
              ),
            ),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: GpTokens.space2),
          Text(
            description!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: centered ? TextAlign.center : TextAlign.start,
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: isError ? GpTokens.space2 : GpTokens.space4),
          GpButton(
            label: actionLabel!,
            variant: GpButtonVariant.secondary,
            fullWidth: false,
            onPressed: onAction,
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      liveRegion: true,
      label: title,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(GpTokens.space4),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(GpTokens.radiusL),
        ),
        child: body,
      ),
    );
  }
}
