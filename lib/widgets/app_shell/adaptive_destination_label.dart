import 'package:flutter/widgets.dart';

/// Picks [shortLabel] instead of [label] when [label] cannot fit in [maxWidth]
/// on a single line and would otherwise truncate with an ellipsis.
String resolveFittingLabel({
  required String label,
  String? shortLabel,
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
  TextScaler textScaler = TextScaler.noScaling,
  Locale? locale,
}) {
  if (shortLabel == null || shortLabel.isEmpty || !maxWidth.isFinite) {
    return label;
  }
  if (maxWidth <= 0) {
    return shortLabel;
  }

  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    maxLines: 1,
    ellipsis: '\u2026',
    textDirection: textDirection,
    textScaler: textScaler,
    locale: locale,
  );
  try {
    painter.layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines ? shortLabel : label;
  } finally {
    painter.dispose();
  }
}

/// Renders [label] on one line, automatically falling back to [shortLabel]
/// when available width would force ellipsis truncation.
class AdaptiveDestinationLabel extends StatelessWidget {
  const AdaptiveDestinationLabel({
    super.key,
    required this.label,
    this.shortLabel,
    required this.style,
    this.textAlign,
    this.preserveFullSemantics = true,
  });

  final String label;
  final String? shortLabel;
  final TextStyle style;
  final TextAlign? textAlign;
  final bool preserveFullSemantics;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle =
        style.inherit ? DefaultTextStyle.of(context).style.merge(style) : style;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final displayText = resolveFittingLabel(
          label: label,
          shortLabel: shortLabel,
          style: effectiveStyle,
          maxWidth: constraints.maxWidth,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        );
        final text = Text(
          displayText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: style,
        );
        if (preserveFullSemantics && displayText != label) {
          return Semantics(
            label: label,
            excludeSemantics: true,
            child: text,
          );
        }
        return text;
      },
    );
  }
}
