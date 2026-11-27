import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';

/// Visual presentation of the faceted geometric TechPie "P" mark.
enum TpBrandMarkVariant {
  /// Sculpted Porcelain (Light) / Obsidian (Dark) squircle jewel carrying
  /// the high-contrast 3D ruby prism "P".
  badge,

  /// Standalone faceted Ruby-Crimson "P" silhouette without the squircle plate.
  glyph,
}

/// Official pure-vector TechPie faceted "P" brand mark.
///
/// Renders a Porcelain-White (Light) or Machined-Obsidian (Dark/AMOLED)
/// squircle plate framing the sculpted 15-facet Ruby Prism "P", keeping
/// TechPie's classic crimson prism unmistakable regardless of system accent.
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
      final radius = BorderRadius.circular(size * 0.25);
      final plateColors = isDark
          ? const [Color(0xFF242429), Color(0xFF16161A), Color(0xFF0E0E11)]
          : const [Color(0xFFFFFFFF), Color(0xFFF4F4F6)];
      final plateBorder = isDark
          ? Colors.white.withValues(alpha: 0.14)
          : const Color(0x16000000);

      mark = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: plateColors,
            stops: isDark ? const [0.0, 0.55, 1.0] : const [0.0, 1.0],
          ),
          boxShadow: showShadow && size >= 20
              ? (isDark
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.48),
                        blurRadius: size * 0.28,
                        offset: Offset(0, size * 0.10),
                      ),
                      BoxShadow(
                        color: TpTokens.techRedDark.withValues(alpha: 0.16),
                        blurRadius: size * 0.30,
                        offset: Offset(0, size * 0.08),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: size * 0.24,
                        offset: Offset(0, size * 0.08),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: size * 0.06,
                        offset: Offset(0, size * 0.02),
                      ),
                      BoxShadow(
                        color: TpTokens.techRedLight.withValues(alpha: 0.08),
                        blurRadius: size * 0.28,
                        offset: Offset(0, size * 0.10),
                      ),
                    ])
              : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isDark)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.05, -0.05),
                      radius: 0.78,
                      colors: [
                        const Color(0xFFE03140).withValues(alpha: 0.24),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.11 : 0.65),
                      Colors.transparent,
                    ],
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
                    border: Border.all(color: plateBorder, width: 0.75),
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

/// Editorial tight-tracked monochrome TechPie wordmark (`Tech` w600 + `Pie` w800).
class TpBrandWordmark extends StatelessWidget {
  const TpBrandWordmark({
    super.key,
    this.fontSize = 17,
    this.textAlign = TextAlign.start,
  });

  final double fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final baseStyle = TpTypography.cardTitle(colors).copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: fontSize >= 20 ? -0.65 : -0.45,
      color: colors.textPrimary,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: 'Tech',
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary.withValues(alpha: 0.90),
            ),
          ),
          const TextSpan(text: 'Pie'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}

/// Micro-caps institution/credit subtitle with optional TechRed terminal accent.
class TpBrandSubtitle extends StatelessWidget {
  const TpBrandSubtitle({
    super.key,
    this.fontSize = 9.5,
    this.prefix = 'SHANGHAITECH',
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
    final accentColor =
        colors.isDark ? TpTokens.techRedDarkInk : TpTokens.techRedLight;
    final baseStyle = TpTypography.cardMeta(colors).copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.35,
      height: 1.15,
      color: colors.textMuted.withValues(alpha: 0.85),
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
    this.markSize = 34,
    this.wordmarkSize = 17,
    this.subtitleSize = 9.5,
    this.showSubtitle = true,
    this.subtitlePrefix = 'SHANGHAITECH',
    this.subtitleAccentSuffix = '',
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
    final resolvedGap = gap ?? 10.0;

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

  static const List<Color> _lightRubyPrism = [
    Color(0xFFF45C69),
    Color(0xFFE03242),
    Color(0xFFC81A2B),
    Color(0xFFA80D1D),
    Color(0xFF830714),
    Color(0xFF5D040E),
  ];

  static const List<Color> _darkRubyPrism = [
    Color(0xFFFF8892),
    Color(0xFFFF5E6C),
    Color(0xFFEA3546),
    Color(0xFFCC1B2B),
    Color(0xFFA81020),
    Color(0xFF820A18),
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
        ..color = (isDark ? Colors.black : const Color(0xFF5D040E))
            .withValues(alpha: isDark ? 0.45 : 0.16)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(isDark ? 1.0 : 0.9, size.height * (isDark ? 0.04 : 0.036)),
        );
      canvas.save();
      canvas.translate(0, size.height * (isDark ? 0.028 : 0.025));
      canvas.drawPath(silhouette, shadowPaint);
      canvas.restore();
    }

    final palette = isDark ? _darkRubyPrism : _lightRubyPrism;
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

    final catchlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(0.55, size.height * 0.017)
      ..color = Colors.white.withValues(alpha: isDark ? 0.36 : 0.28);
    final ridgePath = Path()
      ..moveTo(pt((1, 0)).dx, pt((1, 0)).dy)
      ..lineTo(pt((2, 1)).dx, pt((2, 1)).dy)
      ..lineTo(pt((3, 2)).dx, pt((3, 2)).dy)
      ..moveTo(pt((2, 1)).dx, pt((2, 1)).dy)
      ..lineTo(pt((2, 3)).dx, pt((2, 3)).dy);
    canvas.drawPath(ridgePath, catchlightPaint);
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
