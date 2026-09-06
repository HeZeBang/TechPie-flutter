import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

    final hasLabel = label != null && label!.isNotEmpty;
    final buttonHeight = (height ?? iosMinimumInteractiveDimension).clamp(
      iosMinimumInteractiveDimension,
      double.infinity,
    );
    final buttonWidth = width ?? (hasLabel ? double.infinity : buttonHeight);
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final foreground = switch (role) {
      AdaptiveButtonRole.prominent => CupertinoColors.white,
      AdaptiveButtonRole.destructive => CupertinoColors.systemRed,
      _ => primaryColor,
    };
    final background = switch (role) {
      AdaptiveButtonRole.prominent => primaryColor,
      AdaptiveButtonRole.standard => CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemFill,
          context,
        ),
      AdaptiveButtonRole.plain || AdaptiveButtonRole.destructive => null,
    };
    final enabled = onPressed != null && !loading;

    return Semantics(
      button: true,
      label: accessibilityLabel ?? label,
      enabled: enabled,
      child: SizedBox(
        width: buttonWidth,
        height: buttonHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: CupertinoButton(
            // Retain Flutter 3.27 compatibility; minimumSize was added later.
            // ignore: deprecated_member_use
            minSize: iosMinimumInteractiveDimension,
            padding: EdgeInsets.symmetric(horizontal: hasLabel ? 16 : 0),
            borderRadius: BorderRadius.circular(10),
            onPressed: enabled ? onPressed : null,
            child: _buildIosContent(context, foreground, hasLabel),
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
    final buttonLabel = label;
    if (buttonLabel == null || buttonLabel.isEmpty) {
      return IconButton.filled(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
      );
    }

    final foreground = role == AdaptiveButtonRole.destructive
        ? Theme.of(context).colorScheme.error
        : null;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
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
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size.fromHeight(height ?? 56)),
      foregroundColor:
          foreground == null ? null : WidgetStatePropertyAll(foreground),
    );
    final callback = loading ? null : onPressed;

    return switch (role) {
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
  }
}
