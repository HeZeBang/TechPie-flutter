import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';

/// Visual presentation of the faceted geometric TechPie "P" mark.
enum TpBrandMarkVariant {
  /// Standalone bare faceted TechRed "P" mark directly on the surface.
  glyph,

  /// Flat solid TechRed squircle containing a white faceted "P" mark.
  badge,
}

/// Official pure-vector TechPie faceted "P" brand mark.
///
/// Renders cleanly without decorative shadows or glow boxes, keeping TechPie's
/// signature TechRed geometric mark unmistakable regardless of system accent.
class TpBrandMark extends StatelessWidget {
  const TpBrandMark({
    super.key,
    this.size = 36,
    this.variant = TpBrandMarkVariant.glyph,
    this.showShadow = false,
    this.semanticLabel,
  });

  static const String assetPath = 'assets/icon/icon.png';

  final double size;
  final TpBrandMarkVariant variant;
  final bool showShadow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = context.tpColors.isDark;

    final Widget mark;
    if (variant == TpBrandMarkVariant.glyph) {
      mark = SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _FacetedPBrandPainter(
            whiteMonochrome: false,
            onBadge: false,
            isDark: isDark,
          ),
        ),
      );
    } else {
      final badgeColor =
          isDark ? const Color(0xFFD62839) : TpTokens.techRedLight;
      mark = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(size * 0.24),
        ),
        child: CustomPaint(
          painter: _FacetedPBrandPainter(
            whiteMonochrome: true,
            onBadge: true,
            isDark: isDark,
          ),
        ),
      );
    }

    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: semanticLabel == null,
      child: mark,
    );
  }
}

/// Heavy display-grade monochrome TechPie wordmark.
class TpBrandWordmark extends StatelessWidget {
  const TpBrandWordmark({
    super.key,
    this.fontSize = 17,
    this.textAlign = TextAlign.start,
  });

  static const String brandFontFamily = 'TechPieBrand';

  final double fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Text(
      'TechPie',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: TpTypography.cardTitle(colors).copyWith(
        fontFamily: brandFontFamily,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: fontSize >= 20 ? -0.65 : -0.45,
        color: colors.textPrimary,
      ),
    );
  }
}

/// Quiet secondary institution/credit caption with optional terminal accent.
class TpBrandSubtitle extends StatelessWidget {
  const TpBrandSubtitle({
    super.key,
    this.fontSize = 11.5,
    this.prefix = 'ShanghaiTech · GeekPie',
    this.accentSuffix = '',
    this.textAlign = TextAlign.start,
  });

  final double fontSize;
  final String prefix;
  final String accentSuffix;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final baseStyle = TpTypography.cardMeta(colors).copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
      height: 1.25,
      color: colors.textMuted,
    );

    if (accentSuffix.isEmpty) {
      return Text(
        prefix,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: baseStyle,
      );
    }

    final accentColor =
        colors.isDark ? TpTokens.techRedDarkInk : TpTokens.techRedLight;
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: accentSuffix,
            style: baseStyle.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}

/// TechPie brand lockup pairing [TpBrandMark], [TpBrandWordmark], and an
/// optional quiet [TpBrandSubtitle].
class TpBrandLockup extends StatelessWidget {
  const TpBrandLockup({
    super.key,
    this.markSize = 24,
    this.markVariant = TpBrandMarkVariant.glyph,
    this.wordmarkSize = 16.5,
    this.subtitleSize = 11.5,
    this.showSubtitle = false,
    this.subtitlePrefix = 'ShanghaiTech · GeekPie',
    this.subtitleAccentSuffix = '',
    this.axis = Axis.horizontal,
    this.gap,
  });

  final double markSize;
  final TpBrandMarkVariant markVariant;
  final double wordmarkSize;
  final double subtitleSize;
  final bool showSubtitle;
  final String subtitlePrefix;
  final String subtitleAccentSuffix;
  final Axis axis;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final resolvedGap = gap ?? 8.0;

    if (axis == Axis.vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TpBrandMark(size: markSize, variant: markVariant),
          SizedBox(height: resolvedGap),
          TpBrandWordmark(
            fontSize: wordmarkSize,
            textAlign: TextAlign.center,
          ),
          if (showSubtitle) ...[
            const SizedBox(height: 3),
            TpBrandSubtitle(
              fontSize: subtitleSize,
              prefix: subtitlePrefix,
              accentSuffix: subtitleAccentSuffix,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TpBrandMark(size: markSize, variant: markVariant),
        SizedBox(width: resolvedGap),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TpBrandWordmark(fontSize: wordmarkSize),
              if (showSubtitle) ...[
                const SizedBox(height: 2),
                TpBrandSubtitle(
                  fontSize: subtitleSize,
                  prefix: subtitlePrefix,
                  accentSuffix: subtitleAccentSuffix,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FacetedPBrandPainter extends CustomPainter {
  const _FacetedPBrandPainter({
    required this.whiteMonochrome,
    required this.onBadge,
    required this.isDark,
  });

  final bool whiteMonochrome;
  final bool onBadge;
  final bool isDark;

  static const double _dx = 0.8660254037844386; // sqrt(3) / 2
  static const double _dy = 0.5;

  static const List<(int, int)> _outerLattice = [
    (1, 0),
    (3, 2),
    (3, 4),
    (1, 6),
    (1, 8),
    (0, 9),
    (0, 1),
  ];

  static const List<(int, int)> _innerHoleLattice = [
    (1, 2),
    (2, 3),
    (1, 4),
  ];

  // Exact 15 equilateral triangles matching TechPie's faceted "P" mark.
  static const List<((int, int), (int, int), (int, int), int)> _facets = [
    ((1, 0), (1, 2), (0, 1), 2), // top-left stem cap
    ((0, 1), (0, 3), (1, 2), 3), // upper stem
    ((1, 2), (1, 4), (0, 3), 4), // mid-upper stem
    ((0, 3), (0, 5), (1, 4), 3), // mid stem
    ((1, 4), (1, 6), (0, 5), 4), // mid-lower stem
    ((0, 5), (0, 7), (1, 6), 5), // lower stem
    ((1, 6), (1, 8), (0, 7), 4), // ankle stem
    ((0, 7), (0, 9), (1, 8), 5), // bottom foot
    ((1, 0), (1, 2), (2, 1), 0), // bowl top-left face
    ((2, 1), (2, 3), (1, 2), 1), // bowl upper inner slope
    ((2, 1), (2, 3), (3, 2), 0), // bowl top-right outer face
    ((3, 2), (3, 4), (2, 3), 1), // bowl outer right face
    ((2, 3), (2, 5), (3, 4), 2), // bowl lower right
    ((2, 3), (2, 5), (1, 4), 3), // bowl lower inner slope
    ((1, 4), (1, 6), (2, 5), 4), // bowl underside junction
  ];

  static const List<Color> _lightTechRedFacets = [
    Color(0xFFCF2A39),
    Color(0xFFB91827),
    Color(0xFFA30B19),
    Color(0xFF8D0815),
    Color(0xFF760611),
    Color(0xFF5E040C),
  ];

  static const List<Color> _darkTechRedFacets = [
    Color(0xFFFF737E),
    Color(0xFFF24C5A),
    Color(0xFFE03140),
    Color(0xFFC41E2D),
    Color(0xFFA41220),
    Color(0xFF820B17),
  ];

  static const List<Color> _whiteFacets = [
    Color.fromRGBO(255, 255, 255, 1.0),
    Color.fromRGBO(255, 255, 255, 0.92),
    Color.fromRGBO(255, 255, 255, 0.85),
    Color.fromRGBO(255, 255, 255, 0.78),
    Color.fromRGBO(255, 255, 255, 0.70),
    Color.fromRGBO(255, 255, 255, 0.62),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final glyphH = size.height * (onBadge ? 0.66 : 0.94);
    final unit = glyphH / (9 * _dy);
    final glyphW = 3 * _dx * unit;
    final originX =
        (size.width - glyphW) / 2 + (onBadge ? size.width * 0.02 : 0.0);
    final originY = (size.height - glyphH) / 2;

    Offset pt((int, int) cell) => Offset(
          originX + cell.$1 * _dx * unit,
          originY + cell.$2 * _dy * unit,
        );

    final outerVertices = [for (final c in _outerLattice) pt(c)];
    final outerPath = _buildRoundedPolygon(
      outerVertices,
      cornerRadius: unit * 0.16,
    );
    final holePath = Path()
      ..addPolygon([for (final c in _innerHoleLattice) pt(c)], true);
    final silhouette = Path.combine(
      PathOperation.difference,
      outerPath,
      holePath,
    );

    final palette = whiteMonochrome
        ? _whiteFacets
        : (isDark ? _darkTechRedFacets : _lightTechRedFacets);
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final seamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 0.45;

    canvas.save();
    canvas.clipPath(silhouette);
    for (final facet in _facets) {
      final color = palette[facet.$4];
      fillPaint.color = color;
      seamPaint.color = color;
      final tri = Path()
        ..addPolygon([pt(facet.$1), pt(facet.$2), pt(facet.$3)], true);
      canvas.drawPath(tri, fillPaint);
      canvas.drawPath(tri, seamPaint);
    }
    canvas.restore();
  }

  static Path _buildRoundedPolygon(
    List<Offset> vertices, {
    required double cornerRadius,
  }) {
    final path = Path();
    final count = vertices.length;
    for (var i = 0; i < count; i++) {
      final prev = vertices[(i - 1 + count) % count];
      final curr = vertices[i];
      final next = vertices[(i + 1) % count];
      final inVec = prev - curr;
      final outVec = next - curr;
      final inLen = inVec.distance;
      final outLen = outVec.distance;

      // Cross product > 0 for clockwise vertices in Y-down screen coordinates
      // marks convex exterior corners; keep concave crotch sharp.
      final cross = (-inVec.dx) * outVec.dy - (-inVec.dy) * outVec.dx;
      final radius = cross > 0 && inLen > 0 && outLen > 0
          ? math.min(cornerRadius, math.min(inLen, outLen) * 0.3)
          : 0.0;

      if (radius <= 0) {
        if (i == 0) {
          path.moveTo(curr.dx, curr.dy);
        } else {
          path.lineTo(curr.dx, curr.dy);
        }
      } else {
        final before = curr + inVec * (radius / inLen);
        final after = curr + outVec * (radius / outLen);
        if (i == 0) {
          path.moveTo(before.dx, before.dy);
        } else {
          path.lineTo(before.dx, before.dy);
        }
        path.quadraticBezierTo(curr.dx, curr.dy, after.dx, after.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _FacetedPBrandPainter oldDelegate) =>
      oldDelegate.whiteMonochrome != whiteMonochrome ||
      oldDelegate.onBadge != onBadge ||
      oldDelegate.isDark != isDark;
}
