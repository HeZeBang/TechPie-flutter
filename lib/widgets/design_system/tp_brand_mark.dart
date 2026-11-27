import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';

/// Visual presentation of the faceted geometric TechPie "P" mark.
enum TpBrandMarkVariant {
  /// Iconic TechRed rounded badge carrying the crystalline pearl-white "P".
  badge,

  /// Standalone faceted TechRed "P" silhouette without the rounded tile.
  glyph,
}

/// Official pure-vector TechPie faceted "P" brand mark.
///
/// Always preserves TechPie's iconic TechRed palette regardless of whether
/// the user switches UI controls to system accent colors.
class TpBrandMark extends StatelessWidget {
  const TpBrandMark({
    super.key,
    this.size = 36,
    this.variant = TpBrandMarkVariant.badge,
    this.showShadow = true,
    this.semanticLabel,
  });

  static const String assetPath = 'assets/icon/icon.png';

  final double size;
  final TpBrandMarkVariant variant;
  final bool showShadow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final isDark = colors.isDark;

    final Widget mark;
    if (variant == TpBrandMarkVariant.glyph) {
      mark = SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _FacetedPBrandPainter(onBadge: false, isDark: isDark),
        ),
      );
    } else {
      final radius = BorderRadius.circular(size * 0.24);
      final gradientColors = isDark
          ? const [Color(0xFFF03A4A), Color(0xFFCF1628), Color(0xFF9C0B19)]
          : const [Color(0xFFD91F31), Color(0xFFB50E1E), Color(0xFF8C0714)];
      final rimColor =
          Colors.white.withValues(alpha: isDark ? 0.24 : 0.18);
      final sheenTop =
          Colors.white.withValues(alpha: isDark ? 0.20 : 0.16);

      mark = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
            stops: const [0.0, 0.52, 1.0],
          ),
          boxShadow: showShadow && size >= 20
              ? [
                  BoxShadow(
                    color: TpTokens.techRedLight.withValues(
                      alpha: isDark ? 0.34 : 0.24,
                    ),
                    blurRadius: size * 0.30,
                    offset: Offset(0, size * 0.10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark ? 0.24 : 0.08,
                    ),
                    blurRadius: size * 0.14,
                    offset: Offset(0, size * 0.04),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [sheenTop, Colors.transparent],
                  ),
                ),
              ),
              CustomPaint(
                painter: _FacetedPBrandPainter(onBadge: true, isDark: isDark),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: rimColor, width: 0.75),
                  ),
                ),
              ),
            ],
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

/// Dual-tone TechPie wordmark (`Tech` primary ink + iconic TechRed `Pie`).
class TpBrandWordmark extends StatelessWidget {
  const TpBrandWordmark({
    super.key,
    this.fontSize = 16.5,
    this.textAlign = TextAlign.start,
  });

  final double fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final pieColor =
        colors.isDark ? TpTokens.techRedDarkInk : TpTokens.techRedLight;
    final baseStyle = TpTypography.cardTitle(colors).copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1.1,
      letterSpacing: fontSize >= 20 ? -0.55 : -0.35,
      color: colors.textPrimary,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'Tech'),
          TextSpan(
            text: 'Pie',
            style: baseStyle.copyWith(
              color: pieColor,
              fontWeight: FontWeight.w800,
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

/// GeekPie attribution subtitle with signature trailing TechRed underscore.
class TpBrandSubtitle extends StatelessWidget {
  const TpBrandSubtitle({
    super.key,
    this.fontSize = 11,
    this.prefix = 'by GeekPie',
    this.accentSuffix = '_',
    this.textAlign = TextAlign.start,
  });

  final double fontSize;
  final String prefix;
  final String accentSuffix;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final accentColor =
        (colors.isDark ? TpTokens.techRedDarkInk : TpTokens.techRedLight)
            .withValues(alpha: 0.9);
    final baseStyle = TpTypography.cardMeta(colors).copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.15,
      color: colors.textMuted,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: prefix),
          if (accentSuffix.isNotEmpty)
            TextSpan(
              text: accentSuffix,
              style: baseStyle.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w700,
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

/// Complete TechPie brand lockup pairing [TpBrandMark], [TpBrandWordmark],
/// and an optional [TpBrandSubtitle].
class TpBrandLockup extends StatelessWidget {
  const TpBrandLockup({
    super.key,
    this.markSize = 32,
    this.wordmarkSize = 16.5,
    this.subtitleSize = 11,
    this.showSubtitle = true,
    this.subtitlePrefix = 'by GeekPie',
    this.subtitleAccentSuffix = '_',
    this.axis = Axis.horizontal,
    this.gap,
  });

  final double markSize;
  final double wordmarkSize;
  final double subtitleSize;
  final bool showSubtitle;
  final String subtitlePrefix;
  final String subtitleAccentSuffix;
  final Axis axis;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final resolvedGap = gap ?? (axis == Axis.horizontal ? 10.0 : 10.0);

    if (axis == Axis.vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TpBrandMark(size: markSize),
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
        TpBrandMark(size: markSize),
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
    required this.onBadge,
    required this.isDark,
  });

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
    ((1, 0), (1, 2), (2, 1), 0), // bowl top-left highlight
    ((2, 1), (2, 3), (1, 2), 1), // bowl upper inner slope
    ((2, 1), (2, 3), (3, 2), 0), // bowl top-right peak highlight
    ((3, 2), (3, 4), (2, 3), 1), // bowl outer right face
    ((2, 3), (2, 5), (3, 4), 2), // bowl lower right
    ((2, 3), (2, 5), (1, 4), 3), // bowl lower inner slope
    ((1, 4), (1, 6), (2, 5), 4), // bowl underside junction
  ];

  static const List<Color> _badgePalette = [
    Color(0xFFFFFFFF),
    Color(0xFFFEF4F5),
    Color(0xFFF9E5E8),
    Color(0xFFF2D4D9),
    Color(0xFFE9BFC6),
    Color(0xFFDFABB4),
  ];

  static const List<Color> _lightGlyphPalette = [
    Color(0xFFEC5A65),
    Color(0xFFE0414E),
    Color(0xFFC92533),
    Color(0xFFB01624),
    Color(0xFF910E1A),
    Color(0xFF6F0813),
  ];

  static const List<Color> _darkGlyphPalette = [
    Color(0xFFFF8891),
    Color(0xFFFF6874),
    Color(0xFFF24654),
    Color(0xFFDC2A39),
    Color(0xFFC01B29),
    Color(0xFF9F1220),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final glyphH = size.height * (onBadge ? 0.68 : 0.92);
    final unit = glyphH / (9 * _dy);
    final glyphW = 3 * _dx * unit;
    final originX =
        (size.width - glyphW) / 2 + (onBadge ? size.width * 0.025 : 0.0);
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

    if (onBadge) {
      final shadowPaint = Paint()
        ..color = const Color(0xFF4A030B).withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(0.8, size.height * 0.032),
        );
      canvas.save();
      canvas.translate(0, size.height * 0.022);
      canvas.drawPath(silhouette, shadowPaint);
      canvas.restore();
    }

    final palette = onBadge
        ? _badgePalette
        : (isDark ? _darkGlyphPalette : _lightGlyphPalette);
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
      oldDelegate.onBadge != onBadge || oldDelegate.isDark != isDark;
}
