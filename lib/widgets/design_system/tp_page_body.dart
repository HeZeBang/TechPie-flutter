import 'package:flutter/material.dart';

import '../../theme/tp_tokens.dart';

/// Centers single-column page content within a readable maximum width on wide
/// windows (`singleColumnMaxWidth = 680dp` by default).
class TpPageBody extends StatelessWidget {
  const TpPageBody({
    super.key,
    required this.child,
    this.maxWidth = TpTokens.singleColumnMaxWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Two-column Bento layout at `>= TpTokens.bentoBreakpoint (960dp)`, collapsing
/// cleanly into a single stacked column on narrower viewports.
class TpBentoGrid extends StatelessWidget {
  const TpBentoGrid({
    super.key,
    required this.primaryColumn,
    required this.secondaryColumn,
    this.primaryFlex = 55,
    this.secondaryFlex = 45,
    this.columnGap = TpTokens.space4,
    this.verticalGap = TpTokens.sectionGap,
    this.breakpoint = TpTokens.bentoBreakpoint,
  });

  final List<Widget> primaryColumn;
  final List<Widget> secondaryColumn;
  final int primaryFlex;
  final int secondaryFlex;
  final double columnGap;
  final double verticalGap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < breakpoint) {
      final combined = [...primaryColumn, ...secondaryColumn];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _intersperse(combined, verticalGap),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: primaryFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _intersperse(primaryColumn, verticalGap),
          ),
        ),
        SizedBox(width: columnGap),
        Expanded(
          flex: secondaryFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _intersperse(secondaryColumn, verticalGap),
          ),
        ),
      ],
    );
  }

  List<Widget> _intersperse(List<Widget> widgets, double gap) {
    if (widgets.isEmpty) return const [];
    final result = <Widget>[];
    for (var i = 0; i < widgets.length; i++) {
      if (i > 0) result.add(SizedBox(height: gap));
      result.add(widgets[i]);
    }
    return result;
  }
}
