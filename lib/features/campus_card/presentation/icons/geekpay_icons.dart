import 'package:flutter/material.dart';

/// App-owned vector icon system (Design tokens Part A §7).
/// Each icon is a Material-adjacent tangram drawn as a 2dp-stroke path in a
/// 24dp viewbox, rendered by [GpIconPainter]. Never substitutes Apple SF
/// Symbols or platform assets. Two-layer compositions (stroke geometry plus
/// one filled dot, e.g. [GpIcons.visibilityFill]) are rendered in one pass.
@immutable
sealed class GpIconGeometry {
  const GpIconGeometry();

  List<List<Offset>> get paths;
  bool get filled => false;
}

final class _Path extends GpIconGeometry {
  const _Path(this.paths);

  @override
  final List<List<Offset>> paths;
}

final class _CircleDot extends GpIconGeometry {
  const _CircleDot(this.center, this.radius);
  final Offset center;
  final double radius;

  @override
  List<List<Offset>> get paths => const [];
}

/// Two-layer composition: a stroke [GpIconGeometry] plus an overlay dot
/// ([_CircleDot]) both scaled into the same viewbox, rendered as one icon.
final class _ComposedIcon extends GpIconGeometry {
  const _ComposedIcon(this.base, this.dot);

  final GpIconGeometry base;
  final _CircleDot dot;

  @override
  List<List<Offset>> get paths => base.paths;
}

abstract final class GpIcons {
  static const bill = _Path([
    [Offset(6, 4), Offset(6, 20)],
    [Offset(6, 4), Offset(18, 4)],
    [Offset(18, 4), Offset(18, 20), Offset(6, 20)],
    [Offset(9, 9), Offset(15, 9)],
    [Offset(9, 13), Offset(15, 13)],
    [Offset(9, 17), Offset(13, 17)],
  ]);

  static const me = _Path([
    [Offset(12, 4), Offset(12, 20)],
    [Offset(6.5, 15), Offset(6.5, 20)],
    [Offset(17.5, 15), Offset(17.5, 20)],
    [Offset(6, 7), Offset(18, 7)],
    [Offset(9, 10), Offset(15, 10)],
    [Offset(9.5, 13.5), Offset(14.5, 13.5)],
  ]);

  static const scan = _Path([
    [Offset(5, 5), Offset(19, 5)],
    [Offset(5, 9.5), Offset(19, 9.5)],
    [Offset(5, 14), Offset(19, 14)],
    [Offset(5, 18.5), Offset(19, 18.5)],
  ]);

  static const paymentCode = _Path([
    [Offset(5, 5), Offset(5, 19)],
    [Offset(10.5, 5), Offset(10.5, 19)],
    [Offset(16, 8), Offset(16, 16)],
    [Offset(19, 10.5), Offset(19, 19)],
  ]);

  static const flash = _Path([
    [Offset(5.5, 13), Offset(11, 13)],
    [Offset(11, 4), Offset(18.5, 11)],
    [Offset(18.5, 11), Offset(13, 11)],
    [Offset(13, 11), Offset(13, 19)],
    [Offset(13, 19), Offset(5.5, 13)],
  ]);

  static const gear = _Path([
    [Offset(7, 9), Offset(7, 15), Offset(14, 15)],
    [Offset(7, 9), Offset(14, 9)],
    [Offset(14, 9), Offset(14, 5), Offset(20, 5)],
    [Offset(17, 13), Offset(17, 19)],
    [Offset(4, 12), Offset(4, 16)],
  ]);

  static const lock = _Path([
    [Offset(12, 3.5), Offset(20, 11), Offset(12, 11)],
    [Offset(12, 3.5), Offset(12, 11)],
    [Offset(4, 11), Offset(4, 20), Offset(20, 20), Offset(20, 11)],
    [Offset(4, 11), Offset(12, 11)],
  ]);

  static const info = _Path([
    [Offset(12, 5), Offset(12, 19)],
  ]);

  static const check = _Path([
    [Offset(5, 12.5), Offset(10, 17.5)],
    [Offset(10, 17.5), Offset(19, 6)],
  ]);

  static const chevronRight = _Path([
    [Offset(9, 5), Offset(16, 12)],
    [Offset(16, 12), Offset(9, 19)],
  ]);

  static const chevronLeft = _Path([
    [Offset(15, 5), Offset(8, 12)],
    [Offset(8, 12), Offset(15, 19)],
  ]);

  static const close = _Path([
    [Offset(6, 6), Offset(18, 18)],
    [Offset(18, 6), Offset(6, 18)],
  ]);

  static const refresh = _Path([
    [Offset(5, 13), Offset(12.5, 19), Offset(20, 13)],
    [Offset(5, 13), Offset(5, 7)],
    [Offset(20, 13), Offset(20, 7)],
  ]);

  static const card = _Path([
    [Offset(4, 7), Offset(20, 7)],
    [Offset(4, 7), Offset(4, 18), Offset(20, 18), Offset(20, 7)],
    [Offset(4, 10.5), Offset(20, 10.5)],
    [Offset(7, 15), Offset(11, 15)],
  ]);

  static const offline = _Path([
    [Offset(16, 5), Offset(16, 14)],
    [Offset(12, 10), Offset(16, 14)],
    [Offset(20, 10), Offset(16, 14)],
    [Offset(11, 5), Offset(13, 5)],
    [Offset(13, 18.5), Offset(15, 18.5)],
    [Offset(15, 8.5), Offset(17, 8.5)],
  ]);

  static const person = _Path([
    [Offset(8, 6), Offset(13, 12), Offset(17, 7)],
    [Offset(11.5, 12), Offset(11.5, 19)],
    [Offset(14.5, 12), Offset(14.5, 19)],
    [Offset(12, 10), Offset(9.5, 13.5)],
    [Offset(14, 11), Offset(16, 15)],
  ]);

  static const search = _Path([
    [Offset(4, 6), Offset(10, 12)],
    [Offset(4, 10), Offset(10, 16)],
    [Offset(4, 14), Offset(10, 20)],
    [Offset(14, 8), Offset(20, 14)],
    [Offset(14, 14), Offset(20, 8)],
  ]);

  static const add = _Path([
    [Offset(5, 4), Offset(19, 18)],
    [Offset(19, 4), Offset(5, 18)],
  ]);

  /// Open-eye: almond outline approximated with corner chords, lid curves
  /// suggested by short mid segments; pupil provided by [eyeDot].
  static const visibility = _Path([
    [Offset(3, 12), Offset(7.5, 7.5)],
    [Offset(7.5, 7.5), Offset(12, 6.5), Offset(16.5, 7.5)],
    [Offset(16.5, 7.5), Offset(21, 12)],
    [Offset(21, 12), Offset(16.5, 16.5)],
    [Offset(16.5, 16.5), Offset(12, 17.5), Offset(7.5, 16.5)],
    [Offset(7.5, 16.5), Offset(3, 12)],
  ]);

  /// Closed-eye: same eye base plus a diagonal strike-through.
  static const visibilityOff = _Path([
    [Offset(3, 12), Offset(7.5, 7.5)],
    [Offset(7.5, 7.5), Offset(12, 6.5), Offset(16.5, 7.5)],
    [Offset(16.5, 7.5), Offset(21, 12)],
    [Offset(21, 12), Offset(16.5, 16.5)],
    [Offset(16.5, 16.5), Offset(12, 17.5), Offset(7.5, 16.5)],
    [Offset(7.5, 16.5), Offset(3, 12)],
    [Offset(4.5, 4.5), Offset(19.5, 19.5)],
    [Offset(12, 15.8), Offset(12, 19.2)],
  ]);

  /// Camera-unavailable: camera body with centered "!" and a strike-through.
  static const cameraOff = _Path([
    [Offset(4, 8), Offset(8, 8)],
    [Offset(8, 8), Offset(9.5, 5.5), Offset(14.5, 5.5)],
    [Offset(14.5, 5.5), Offset(16, 8), Offset(20, 8)],
    [Offset(4, 8), Offset(4, 18.5), Offset(20, 18.5), Offset(20, 8)],
    [Offset(12, 9.5), Offset(12, 12.5)],
    [Offset(4, 4), Offset(20, 20)],
  ]);

  static const qrDot = _CircleDot(Offset(12, 10), 2);
  static const infoDot = _CircleDot(Offset(12, 6.5), 1);
  static const personDot = _CircleDot(Offset(12, 5.5), 1);
  static const eyeDot = _CircleDot(Offset(12, 12), 1.6);
  static const cameraDot = _CircleDot(Offset(12, 14.6), 0.9);

  /// visibility with filled pupil.
  static const GpIconGeometry visibilityFill = _ComposedIcon(
    visibility,
    eyeDot,
  );

  /// cameraOff with filled exclamation dot.
  static const GpIconGeometry cameraOffFill = _ComposedIcon(
    cameraOff,
    cameraDot,
  );
}

class GpIcon extends StatelessWidget {
  const GpIcon(this.geometry, {super.key, this.size = 24, this.color});

  final GpIconGeometry geometry;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? Colors.black;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final node = Semantics(
      container: true,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          painter: GpIconPainter(geometry, resolved, dark: dark),
        ),
      ),
    );
    return SizedBox.square(dimension: size, child: node);
  }
}

final class GpIconPainter extends CustomPainter {
  GpIconPainter(this.geometry, this.color, {required this.dark});

  final GpIconGeometry geometry;
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2 * k
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter
      ..strokeCap = StrokeCap.square;
    for (final path in geometry.paths) {
      final built = Path();
      for (var i = 0; i < path.length; i++) {
        final point = path[i] * k;
        if (i == 0) {
          built.moveTo(point.dx, point.dy);
        } else {
          built.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        built,
        geometry.filled ? (Paint()..color = color) : stroke,
      );
    }
    if (geometry is _CircleDot) {
      final dot = geometry as _CircleDot;
      canvas.drawCircle(dot.center * k, dot.radius * k, Paint()..color = color);
    }
    if (geometry is _ComposedIcon) {
      final dot = (geometry as _ComposedIcon).dot;
      canvas.drawCircle(dot.center * k, dot.radius * k, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(GpIconPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.color != color ||
      oldDelegate.dark != dark;
}
