import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:techpie/theme/theme.dart';
import 'package:techpie/utils/platform.dart';

import 'cupertino_symbol_icons.dart';

enum AdaptiveButtonRole { prominent, standard, plain, destructive }

class AdaptiveButton extends StatelessWidget {
  const AdaptiveButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.sfSymbol,
    this.label,
    this.subtitle,
    this.role = AdaptiveButtonRole.standard,
    this.loading = false,
    this.width,
    this.height,
    this.accessibilityLabel,
    this.showIosIcon = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String sfSymbol;
  final String? label;
  final String? subtitle;
  final AdaptiveButtonRole role;
  final bool loading;
  final double? width;
  final double? height;
  final String? accessibilityLabel;
  final bool showIosIcon;

  @override
  Widget build(BuildContext context) {
    if (!isIos()) return _buildMaterialButton(context);

    final colors = context.tpColors;
    final hasLabel = label != null && label!.isNotEmpty;
    final buttonHeight = (height ?? iosMinimumInteractiveDimension).clamp(
      iosMinimumInteractiveDimension,
      double.infinity,
    );
    final buttonWidth = width ?? (hasLabel ? double.infinity : buttonHeight);
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final foreground = switch (role) {
      AdaptiveButtonRole.prominent => colors.onBrand,
      AdaptiveButtonRole.destructive => colors.dangerRed,
      _ => colors.brandInk,
    };
    final background = switch (role) {
      AdaptiveButtonRole.prominent => primaryColor,
      AdaptiveButtonRole.standard => colors.opaqueBrandContainer,
      AdaptiveButtonRole.plain || AdaptiveButtonRole.destructive => null,
    };
    final enabled = onPressed != null && !loading;

    return Semantics(
      button: true,
      label: accessibilityLabel ?? label,
      enabled: enabled,
      child: Opacity(
        opacity: enabled || loading ? 1.0 : 0.45,
        child: SizedBox(
          width: buttonWidth,
          height: buttonHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(TpTokens.radiusS),
            ),
            child: CupertinoButton(
              minimumSize: const Size.square(iosMinimumInteractiveDimension),
              padding: EdgeInsets.symmetric(horizontal: hasLabel ? 16 : 0),
              borderRadius: BorderRadius.circular(TpTokens.radiusS),
              onPressed: enabled ? onPressed : null,
              child: _buildIosContent(context, foreground, hasLabel),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIosContent(
    BuildContext context,
    Color foreground,
    bool hasLabel,
  ) {
    if (loading) {
      return CupertinoActivityIndicator(color: foreground);
    }

    final symbol = Icon(
      cupertinoIconForSfSymbol(sfSymbol, fallback: icon),
      size: 20,
      color: foreground,
    );
    if (!hasLabel) return symbol;

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CupertinoTheme.of(context).textTheme.actionTextStyle.copyWith(
                color: foreground,
                fontWeight: role == AdaptiveButtonRole.prominent
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
        ),
        if (subtitle case final subtitle? when subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: foreground.withValues(alpha: 0.72),
                  fontSize: 12,
                ),
          ),
      ],
    );

    if (!showIosIcon) return text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [symbol, const SizedBox(width: 8), Flexible(child: text)],
    );
  }

  Widget _buildMaterialButton(BuildContext context) {
    final colors = context.tpColors;
    final scheme = Theme.of(context).colorScheme;
    final buttonLabel = label;
    final callback = loading ? null : onPressed;

    if (buttonLabel == null || buttonLabel.isEmpty) {
      final iconWidget = loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon);
      final Widget iconButton = switch (role) {
        AdaptiveButtonRole.prominent => IconButton.filled(
            onPressed: callback,
            tooltip: accessibilityLabel,
            icon: iconWidget,
          ),
        AdaptiveButtonRole.standard => IconButton.filledTonal(
            onPressed: callback,
            tooltip: accessibilityLabel,
            icon: iconWidget,
          ),
        AdaptiveButtonRole.plain => IconButton(
            onPressed: callback,
            tooltip: accessibilityLabel,
            icon: iconWidget,
          ),
        AdaptiveButtonRole.destructive => IconButton(
            onPressed: callback,
            tooltip: accessibilityLabel,
            color: colors.dangerRed,
            icon: iconWidget,
          ),
      };
      return width == null && height == null
          ? iconButton
          : SizedBox(width: width, height: height, child: iconButton);
    }

    final child = Builder(
      builder: (innerContext) {
        final inheritedFg = DefaultTextStyle.of(innerContext).style.color;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: width == null ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (loading)
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: inheritedFg,
                ),
              )
            else
              Icon(icon),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(buttonLabel),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: Theme.of(innerContext)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: inheritedFg?.withValues(alpha: 0.78)),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        width != null
            ? Size(width!, height ?? 48)
            : Size.fromHeight(height ?? 56),
      ),
      foregroundColor: role == AdaptiveButtonRole.destructive
          ? WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return scheme.onSurface.withValues(alpha: 0.38);
              }
              return colors.dangerRed;
            })
          : null,
    );

    final Widget button = switch (role) {
      AdaptiveButtonRole.prominent =>
        FilledButton(onPressed: callback, style: style, child: child),
      AdaptiveButtonRole.standard => FilledButton.tonal(
          onPressed: callback,
          style: style,
          child: child,
        ),
      AdaptiveButtonRole.plain ||
      AdaptiveButtonRole.destructive =>
        TextButton(onPressed: callback, style: style, child: child),
    };

    final sized = width == null ? button : SizedBox(width: width, child: button);
    return accessibilityLabel == null
        ? sized
        : Semantics(label: accessibilityLabel, child: sized);
  }
}
