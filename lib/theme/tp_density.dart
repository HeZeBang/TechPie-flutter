import 'package:flutter/widgets.dart';

import '../utils/platform.dart';
import 'tp_tokens.dart';

/// Responsive UI density preset separating touch-first mobile geometry from
/// mouse/keyboard-driven desktop workbenches.
@immutable
final class TpDensity {
  const TpDensity({
    required this.isCompact,
    required this.cardPaddingHorizontal,
    required this.cardPaddingVertical,
    required this.rowVerticalPadding,
    required this.rowMinHeight,
    required this.sectionGap,
    required this.pageHorizontalPadding,
    required this.iconSize,
  });

  /// Touch-friendly metrics matching Apple HIG & Material mobile targets.
  static const TpDensity comfortable = TpDensity(
    isCompact: false,
    cardPaddingHorizontal: TpTokens.cardPaddingHorizontal,
    cardPaddingVertical: TpTokens.cardPaddingVertical,
    rowVerticalPadding: 12,
    rowMinHeight: 48,
    sectionGap: TpTokens.sectionGap,
    pageHorizontalPadding: TpTokens.pageHorizontalPadding,
    iconSize: TpTokens.iconM,
  );

  /// Tighter desktop workbench metrics for pointer + keyboard precision.
  static const TpDensity compact = TpDensity(
    isCompact: true,
    cardPaddingHorizontal: 14,
    cardPaddingVertical: 12,
    rowVerticalPadding: 9,
    rowMinHeight: 38,
    sectionGap: 10,
    pageHorizontalPadding: TpTokens.pageHorizontalPaddingWide,
    iconSize: 18,
  );

  final bool isCompact;
  final double cardPaddingHorizontal;
  final double cardPaddingVertical;
  final double rowVerticalPadding;
  final double rowMinHeight;
  final double sectionGap;
  final double pageHorizontalPadding;
  final double iconSize;

  EdgeInsets get cardPadding => EdgeInsets.symmetric(
        horizontal: cardPaddingHorizontal,
        vertical: cardPaddingVertical,
      );

  EdgeInsets get cardHeaderPadding => EdgeInsets.fromLTRB(
        cardPaddingHorizontal,
        cardPaddingVertical,
        cardPaddingHorizontal,
        TpTokens.space2,
      );

  EdgeInsets get rowPadding => EdgeInsets.symmetric(
        horizontal: cardPaddingHorizontal,
        vertical: rowVerticalPadding,
      );

  static TpDensity of(BuildContext context) =>
      TpDensityScope.maybeOf(context) ?? (isDesktop() ? compact : comfortable);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TpDensity &&
        other.isCompact == isCompact &&
        other.cardPaddingHorizontal == cardPaddingHorizontal &&
        other.cardPaddingVertical == cardPaddingVertical &&
        other.rowVerticalPadding == rowVerticalPadding &&
        other.rowMinHeight == rowMinHeight &&
        other.sectionGap == sectionGap &&
        other.pageHorizontalPadding == pageHorizontalPadding &&
        other.iconSize == iconSize;
  }

  @override
  int get hashCode => Object.hash(
        isCompact,
        cardPaddingHorizontal,
        cardPaddingVertical,
        rowVerticalPadding,
        rowMinHeight,
        sectionGap,
        pageHorizontalPadding,
        iconSize,
      );
}

/// Overrides the resolved [TpDensity] for a subtree (e.g. dense popovers or tests).
class TpDensityScope extends InheritedWidget {
  const TpDensityScope({
    super.key,
    required this.density,
    required super.child,
  });

  final TpDensity density;

  static TpDensity? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TpDensityScope>()?.density;

  @override
  bool updateShouldNotify(covariant TpDensityScope oldWidget) =>
      density != oldWidget.density;
}

extension TpDensityContext on BuildContext {
  TpDensity get tpDensity => TpDensity.of(this);
}
