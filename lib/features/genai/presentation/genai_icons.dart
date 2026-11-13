import 'package:flutter/material.dart';

/// The design draft's 24 × 24, stroke-only icon sprite.
///
/// Path strings and primitive coordinates for the original symbols are copied
/// verbatim from artifacts/genai-ui-draft/index.html. Additional glyphs use the
/// same grid and stroke treatment.
enum GenAiGlyph {
  plus('M12 5v14M5 12h14'),
  chat('M5 5h14v11H9l-4 4V5Z'),
  edit('m14 5 5 5M12 7l5-5 5 5-5 5-9 9H3v-5L12 7ZM10 3H4a1 1 0 0 0-1 1v6M14 21h7v-7'),
  search('m15 15 5 5', circles: [_Circle(10, 10, 6)]),
  image('m3 17 5-5 4 4 4-6 5 7', circles: [_Circle(8, 8, 1.5)], rects: [_Rect(3, 3, 18, 18, 3)]),
  chevron('m8 5 7 7-7 7'),
  down('m6 9 6 6 6-6'),
  more('', circles: [_Circle(5, 12, 1), _Circle(12, 12, 1), _Circle(19, 12, 1)]),
  close('m6 6 12 12M6 18 18 6'),
  sidebar('M9 4v16', rects: [_Rect(3, 4, 18, 16, 3)]),
  arrow('M12 19V5m-6 6 6-6 6 6'),
  back('M20 12H4m6-6-6 6 6 6'),
  check('m5 12 4 4L19 6'),
  brain('M9 18v3h7v-5c4-2 4-8 1-11-3-4-9-3-11 1-1 2-1 4-2 6l-1 2h3v4h3ZM12 6v8M9 8l6 4M9 12l6-4'),
  tools('m12 3 2.3 6.7L21 12l-6.7 2.3L12 21l-2.3-6.7L3 12l6.7-2.3L12 3Z'),
  mic('M5 10v2a7 7 0 0 0 14 0v-2M12 19v3', rects: [_Rect(9, 2, 6, 12, 3)]),
  copy('M15 8V3H3v12h5', rects: [_Rect(8, 8, 12, 13, 2)]),
  full('M3 9V3h6M15 3h6v6M21 15v6h-6M9 21H3v-6'),
  code('m8 6-6 6 6 6m8-12 6 6-6 6M14 3l-4 18'),
  retry('M20 10a8 8 0 1 0 0 6M20 4v6h-6'),
  speaker('m11 4-6 5H2v6h3l6 5V4ZM15 8c3 2 3 6 0 8M18 4c6 4 6 12 0 16'),
  file('M13 2H5v20h14V8l-6-6Zm0 0v6h6M8 13h8M8 17h6'),
  calendar('M7 2v6M17 2v6M3 11h18M7 15h3M14 15h3', rects: [_Rect(3, 5, 18, 16, 2)]),
  clock('M12 6v6l4 2', circles: [_Circle(12, 12, 9)]),
  user('M4 21v-2a8 8 0 0 1 16 0v2', circles: [_Circle(12, 8, 4)]),
  moon('M20 14A9 9 0 0 1 10 3 9 9 0 1 0 20 14Z'),
  download('M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5'),
  share('M12 15V2m-4 4 4-4 4 4M6 10H3v12h18V10h-3'),
  trash('M3 6h18M8 6V3h8v3M5 6l1 15h12l1-15M10 10v7M14 10v7'),
  info('M12 11v6M12 7v1', circles: [_Circle(12, 12, 9)]),
  lock('M8 10V6a4 4 0 0 1 8 0v4M12 14v3', rects: [_Rect(5, 10, 14, 11, 2)]),

  link('M10 14a4 4 0 0 0 6 0l4-4a4 4 0 0 0-6-6l-2 2M14 10a4 4 0 0 0-6 0l-4 4a4 4 0 0 0 6 6l2-2'),
  unlink(
    'M8 3v3M3 8h3M16 18v3M18 16h3M9 15l-1 1a4 4 0 0 1-6-6l3-3M15 9l1-1a4 4 0 0 1 6 6l-3 3M3 3l18 18',
  ),
  openExternal('M14 3h7v7M21 3l-11 11M10 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-5'),
  stop('', rects: [_Rect(5, 5, 14, 14, 3)]),
  refresh('M20 10a8 8 0 1 0 0 6M20 4v6h-6'),
  undo('M9 4 3 10l6 6M3 10h11a6 6 0 0 1 0 12'),
  logout('M9 3H4v18h5M9 12h12m-5-5 5 5-5 5'),
  chevronLeft('m16 5-7 7 7 7'),
  minus('M5 12h14'),
  sync('M20 10a8 8 0 0 0-14-4M4 14a8 8 0 0 0 14 4M20 4v6h-6M4 20v-6h6'),
  warning('M12 3 22 21H2L12 3ZM12 9v5M12 17v1'),
  fullExit('M9 3v6H3M21 9h-6V3M15 21v-6h6M3 15h6v6'),
  audio('M13 2H5v20h14V8l-6-6Zm0 0v6h6M8 14v2M11 12v6M14 13v4M17 14v2'),
  chart('M4 3v18h17M8 17v-5M13 17V7M18 17V4'),
  diagram(
    'M12 8v4M5 16v-4h14v4',
    rects: [_Rect(9, 2, 6, 6, 1.5), _Rect(2, 16, 6, 6, 1.5), _Rect(16, 16, 6, 6, 1.5)],
  ),
  zoomIn('m15 15 5 5M7 10h6M10 7v6', circles: [_Circle(10, 10, 6)]),
  zoomOut('m15 15 5 5M7 10h6', circles: [_Circle(10, 10, 6)]),
  fit('M3 9V3h6M15 3h6v6M21 15v6h-6M9 21H3v-6', circles: [_Circle(12, 12, 1)]),
  school('M2 9 12 4l10 5-10 5L2 9ZM6 11v6q6 5 12 0v-6M22 9v8'),
  checkCircle('m7 12 3 3 7-7', circles: [_Circle(12, 12, 9)]);

  const GenAiGlyph(this._data, {List<_Circle> circles = const [], List<_Rect> rects = const []})
    : _circles = circles,
      _rects = rects;

  final String _data;
  final List<_Circle> _circles;
  final List<_Rect> _rects;

  // Compatibility names for call sites whose Material names differ from SVG IDs.
  static const add = plus;
  static const delete = trash;
  static const brokenImage = image;
}

class _Circle {
  const _Circle(this.x, this.y, this.radius);
  final double x;
  final double y;
  final double radius;
}

class _Rect {
  const _Rect(this.x, this.y, this.width, this.height, this.radius);
  final double x;
  final double y;
  final double width;
  final double height;
  final double radius;
}

/// A font-independent icon that inherits button, menu and list-tile icon themes.
class GenAiIcon extends StatelessWidget {
  const GenAiIcon(this.glyph, {super.key, this.size, this.color, this.semanticLabel});

  final GenAiGlyph glyph;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final extent = size ?? theme.size ?? 24;
    var resolvedColor = color ?? theme.color ?? const Color(0xff000000);
    final opacity = theme.opacity ?? 1;
    if (opacity != 1) resolvedColor = resolvedColor.withValues(alpha: resolvedColor.a * opacity);
    final child = SizedBox.square(
      dimension: extent,
      child: Center(
        child: CustomPaint(
          size: Size.square(extent),
          painter: _GenAiIconPainter(glyph, resolvedColor),
        ),
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: child)
        : Semantics(
            label: semanticLabel,
            child: ExcludeSemantics(child: child),
          );
  }

  @visibleForTesting
  static Path debugParsePath(String data) => _parsePath(data);
}

class _GenAiIconPainter extends CustomPainter {
  const _GenAiIconPainter(this.glyph, this.color);
  final GenAiGlyph glyph;
  final Color color;
  static final Map<GenAiGlyph, Path> _paths = {};

  static Path pathFor(GenAiGlyph glyph) => _paths.putIfAbsent(glyph, () {
    final path = _parsePath(glyph._data);
    for (final circle in glyph._circles) {
      path.addOval(Rect.fromCircle(center: Offset(circle.x, circle.y), radius: circle.radius));
    }
    for (final rect in glyph._rects) {
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.x, rect.y, rect.width, rect.height),
          Radius.circular(rect.radius),
        ),
      );
    }
    return path;
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      pathFor(glyph),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GenAiIconPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}

/// SVG path reader. Repeated coordinates implicitly repeat the last command;
/// subsequent moveto pairs are lineto pairs, including relative moveto.
Path _parsePath(String data) {
  final tokens = RegExp(
    r'[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?',
  ).allMatches(data).map((match) => match.group(0)!).toList();
  final path = Path();
  var index = 0;
  var command = '';
  var previous = '';
  var current = Offset.zero;
  var start = Offset.zero;
  var cubicControl = Offset.zero;
  var quadraticControl = Offset.zero;
  bool isCommand(String token) => RegExp(r'^[a-zA-Z]$').hasMatch(token);
  double number() {
    if (index >= tokens.length || isCommand(tokens[index])) {
      throw FormatException('Missing SVG path coordinate for $command', data);
    }
    return double.parse(tokens[index++]);
  }

  Offset point(bool relative) {
    final value = Offset(number(), number());
    return relative ? current + value : value;
  }

  while (index < tokens.length) {
    if (isCommand(tokens[index])) command = tokens[index++];
    final upper = command.toUpperCase();
    final relative = command != upper;
    switch (upper) {
      case 'M':
        current = point(relative);
        start = current;
        path.moveTo(current.dx, current.dy);
        command = relative ? 'l' : 'L';
      case 'L':
        current = point(relative);
        path.lineTo(current.dx, current.dy);
      case 'H':
        final x = number();
        current = Offset(relative ? current.dx + x : x, current.dy);
        path.lineTo(current.dx, current.dy);
      case 'V':
        final y = number();
        current = Offset(current.dx, relative ? current.dy + y : y);
        path.lineTo(current.dx, current.dy);
      case 'C':
        final first = point(relative);
        final second = point(relative);
        final end = point(relative);
        path.cubicTo(first.dx, first.dy, second.dx, second.dy, end.dx, end.dy);
        cubicControl = second;
        current = end;
      case 'S':
        final first = previous == 'C' || previous == 'S' ? current * 2 - cubicControl : current;
        final second = point(relative);
        final end = point(relative);
        path.cubicTo(first.dx, first.dy, second.dx, second.dy, end.dx, end.dy);
        cubicControl = second;
        current = end;
      case 'Q':
        final control = point(relative);
        final end = point(relative);
        path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        quadraticControl = control;
        current = end;
      case 'T':
        final control = previous == 'Q' || previous == 'T'
            ? current * 2 - quadraticControl
            : current;
        final end = point(relative);
        path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        quadraticControl = control;
        current = end;
      case 'A':
        final rx = number().abs();
        final ry = number().abs();
        final rotation = number();
        final large = number() != 0;
        final clockwise = number() != 0;
        final end = point(relative);
        if (rx == 0 || ry == 0) {
          path.lineTo(end.dx, end.dy);
        } else if (end != current) {
          path.arcToPoint(
            end,
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: large,
            clockwise: clockwise,
          );
        }
        current = end;
      case 'Z':
        path.close();
        current = start;
        command = '';
      default:
        throw FormatException('Unsupported SVG path command $command', data);
    }
    previous = upper;
  }
  return path;
}
