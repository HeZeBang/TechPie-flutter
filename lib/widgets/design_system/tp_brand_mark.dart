import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';

/// Official TechPie geometric "P" brand mark backed by `assets/icon/icon.png`.
///
/// Renders cleanly on both light and dark surfaces without an artificial
/// bounding box, matching the TechPie website navbar identity.
class TpBrandMark extends StatelessWidget {
  const TpBrandMark({
    super.key,
    this.size = 36,
    this.semanticLabel,
  });

  static const String assetPath = 'assets/icon/icon.png';

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: (context, _, __) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.opaqueBrandContainer,
          borderRadius: BorderRadius.circular(TpTokens.radiusS),
        ),
        alignment: Alignment.center,
        child: Text(
          'P',
          style: TpTypography.cardTitle(colors).copyWith(
            color: colors.brandInk,
            fontSize: size * 0.56,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
