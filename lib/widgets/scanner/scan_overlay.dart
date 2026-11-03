import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// The scanner's viewfinder, reproduced from Telegram's `CameraScanActivity`.
///
/// Three animated scalars drive it:
///
/// * [appearing] — a spring started when the preview is ready. The box grows
///   from half size while the four brackets retract into short rounded ticks.
/// * [dismissed] — fades only the title, hint, and controls after recognition.
/// * [absorbed] — a spring that morphs the box onto the decoded code corners.
///
/// The scrim's opening is rounded to the same radius as the corner marks'
/// outer edge, so the dimmed area and the brackets read as one frame. The
/// startup cover is the page's, because it has to sit above the chrome too.
///
/// The numbers are the ones in Telegram's source: `lineLength` eases with
/// `pow(v, 1.8)`, the stroke reaches 4dp within 5% of the appearing spring, the
/// resting square is `min(w, h) / 1.5`, and the found-code target is padded
/// 25dp horizontally and 15dp vertically.
final class ScanOverlay extends StatefulWidget {
  const ScanOverlay({
    super.key,
    required this.child,
    required this.appearing,
    required this.dismissed,
    required this.absorbed,
    this.target,
    this.windowFor,
    this.dimOpacity = 0.5,
    this.accent = Colors.white,
    this.painterKey,
  });

  final Widget child;
  final Animation<double> appearing;
  final Animation<double> dismissed;
  final Animation<double> absorbed;
  final List<Offset>? target;
  final Rect Function(Size size)? windowFor;
  final double dimOpacity;
  final Color accent;
  final Key? painterKey;

  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

final class _ScanOverlayState extends State<ScanOverlay> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              widget.appearing,
              widget.dismissed,
              widget.absorbed,
            ]),
            builder: (context, _) => CustomPaint(
              key: widget.painterKey,
              painter: ScanOverlayPainter(
                appearing: widget.appearing.value.clamp(0.0, 1.4),
                dismissed: widget.dismissed.value.clamp(0.0, 1.0),
                absorbed: widget.absorbed.value.clamp(0.0, 1.0),
                target: widget.target,
                windowFor: widget.windowFor,
                dimOpacity: widget.dimOpacity,
                accent: widget.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Drives the scalars for a scanner screen and disposes them together.
///
/// Kept separate from [ScanOverlay] so a page can start `appearing` when its
/// preview reports its first frame, and `absorbed`/`dismissed` when a code is
/// decoded — the same triggers Telegram uses. [restarting] is the startup cover
/// the page paints above its chrome: opaque until the preview is live.
final class ScanOverlayController {
  ScanOverlayController({
    required TickerProvider vsync,
    this.restingWindowBuilder,
  })  : appearing = AnimationController.unbounded(vsync: vsync, value: 0),
        dismissed = AnimationController.unbounded(vsync: vsync, value: 0),
        absorbed = AnimationController.unbounded(vsync: vsync, value: 0),
        restarting = AnimationController.unbounded(vsync: vsync, value: 1);

  final AnimationController appearing;
  final AnimationController dismissed;
  final AnimationController absorbed;
  final AnimationController restarting;

  final Rect Function(Size size)? restingWindowBuilder;

  static final SpringDescription _appearingSpring = SpringDescription(
    mass: 1,
    stiffness: 250,
    damping: 2 * math.sqrt(250) * 0.8,
  );
  static final SpringDescription _absorbedSpring = SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 2 * math.sqrt(500),
  );

  /// Telegram's curve for the found-code fade.
  static const Curve foundCurve = Cubic(0.25, 0.1, 0.25, 1);

  void startAppearing() {
    appearing.value = 0;
    unawaited(
      appearing.animateWith(
        SpringSimulation(_appearingSpring, 0, 1, 0),
      ),
    );
  }

  void resetFrame() {
    appearing.stop();
    dismissed.stop();
    absorbed.stop();
    appearing.value = 0;
    dismissed.value = 0;
    absorbed.value = 0;
  }

  void beginCameraStart() {
    restarting.stop();
    restarting.value = 1;
    resetFrame();
  }

  Future<void> finishCameraStart() => restarting.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );

  void revealCameraImmediately() {
    restarting.stop();
    restarting.value = 0;
  }

  void reset() {
    resetFrame();
    restarting.stop();
    restarting.value = 1;
  }

  /// Recognition moves the frame and fades the chrome. ScannerPage freezes the
  /// captured image separately before stopping the camera.
  void setFound(bool found) {
    final from = found ? absorbed.value : 1 - absorbed.value;
    unawaited(
      absorbed.animateWith(
        SpringSimulation(_absorbedSpring, from, found ? 1 : 0, 0),
      ),
    );
    unawaited(
      dismissed.animateTo(
        found ? 1 : 0,
        duration: Duration(
          milliseconds: (300 * (found ? 1 - dismissed.value : dismissed.value))
              .round()
              .clamp(1, 300),
        ),
        curve: foundCurve,
      ),
    );
  }

  void dispose() {
    appearing.dispose();
    dismissed.dispose();
    absorbed.dispose();
    restarting.dispose();
  }
}

/// Paints the scrim, the box and the four corner brackets.
///
/// God object by design: this is one pass of a canvas, and splitting it would
/// only spread the same maths over three files.
final class ScanOverlayPainter extends CustomPainter {
  ScanOverlayPainter({
    required this.appearing,
    required this.dismissed,
    required this.absorbed,
    required this.target,
    required this.windowFor,
    required this.dimOpacity,
    required this.accent,
  });

  final double appearing;
  final double dismissed;
  final double absorbed;
  final List<Offset>? target;
  final Rect Function(Size size)? windowFor;
  final double dimOpacity;
  final Color accent;

  /// Telegram's resting square: `min(w, h) / 1.5`, centred, in logical pixels.
  static Rect restingSquare(Size size) {
    final side = math.min(size.width, size.height) / 1.5;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side,
      height: side,
    );
  }

  /// The box while it appears: half size at 0, full size at 1.
  static double appearingScale(double appearing) =>
      0.5 + appearing.clamp(0.0, 1.0) * 0.5;

  /// The bracket stroke in logical pixels: Telegram reaches the full 4dp within
  /// the first 5% of the spring (`min(1, v * 20)`), so the ticks look like they
  /// are already there as the box grows.
  static double bracketStroke(double appearing) =>
      ui.lerpDouble(0, 4, math.min(1, appearing * 20))!;

  /// The bracket arm length: a whole box edge at rest, retracting to 20dp with
  /// Telegram's `pow(v, 1.8)`. This retraction *is* the opening animation.
  static double bracketLength(double side, double appearing) => ui.lerpDouble(
        side,
        20,
        math.min(1.2, math.pow(appearing.clamp(0.0, 1.2), 1.8).toDouble()),
      )!;

  /// The radius of the window's corners: the corner marks' outer edge.
  ///
  /// A mark's centre line runs 1.5 strokes from the elbow's centre
  /// ([bracketElbow]) and the stroke reaches half a stroke further out, so its
  /// outer edge sits 2 strokes from the centre — rounding the scrim's opening to
  /// that radius makes the dimmed area and the marks one shape.
  static double windowRadius(double stroke) => stroke * 2;

  /// The radius of a bracket's centre line. Telegram's elbow puts the outer edge
  /// at 2 strokes and the inner edge at 1, which is concentric because both are
  /// arcs around the same centre — the half stroke of the stroke itself is what
  /// separates them.
  static double bracketElbow(double stroke) => windowRadius(stroke) - stroke / 2;

  /// The found code's bounds, padded the way Telegram pads them: 25dp across,
  /// 15dp down, in logical pixels.
  static Rect paddedTarget(
    List<Offset> corners,
    Size size, {
    double padX = 25,
    double padY = 15,
  }) {
    var left = corners.first.dx, right = corners.first.dx;
    var top = corners.first.dy, bottom = corners.first.dy;
    for (final point in corners) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(
      left * size.width - padX,
      top * size.height - padY,
      right * size.width + padX,
      bottom * size.height + padY,
    ).intersect(Offset.zero & size);
  }

  /// Blends the resting square onto the found target.
  static Rect blendFrame(Rect rest, Rect? found, double absorbed) =>
      found == null || absorbed <= 0
          ? rest
          : Rect.lerp(rest, found, absorbed.clamp(0.0, 1.0))!;

  /// The frame to draw: the resting square while nothing is found, the code's
  /// own bounds once something is, blended by [absorbed].
  Rect _frame(Size size) {
    final rest = (windowFor ?? restingSquare)(size);
    final corners = target;
    return blendFrame(
      rest,
      corners == null || corners.isEmpty ? null : paddedTarget(corners, size),
      absorbed,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The box grows from half size while it appears.
    final frame = _frame(size);
    final scale = appearingScale(appearing);
    final box = Rect.fromCenter(
      center: frame.center,
      width: frame.width * scale,
      height: frame.height * scale,
    );

    final progress = appearing.clamp(0.0, 1.2);
    final stroke = bracketStroke(progress);
    final length = bracketLength(math.min(box.width, box.height), progress);
    final window = RRect.fromRectAndRadius(
      box,
      Radius.circular(windowRadius(stroke)),
    );

    // Scrim: everything outside the window, then the window interior, which the
    // appearing spring fades out and a found code keeps dark.
    // Recognition keeps the live preview visible. Only the explicit rescan
    // state may deepen the scrim, and it fades the whole surface uniformly.
    final scrim = Paint()
      ..color = Colors.black.withValues(alpha: dimOpacity.clamp(0.0, 1.0));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(window),
      scrim,
    );
    final inner = Paint()
      ..color = Colors.black.withValues(
        alpha: (dimOpacity * (1 - appearing.clamp(0.0, 1.0))).clamp(0.0, 1.0),
      );
    canvas.drawRRect(window, inner);

    // Nothing to mark until the stroke has a width: `arcToPoint` has no arc to
    // draw at a zero radius.
    if (stroke <= 0) {
      return;
    }

    final bracket = Paint()
      ..color = accent.withValues(alpha: math.min(1, progress))
      // Telegram's bracket reads as a thick line with round ends and a rounded
      // elbow; a stroked L gives exactly that, where a filled path only
      // approximates it.
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    _bracket(canvas, bracket, box.topLeft, 1, 1, stroke, length);
    _bracket(canvas, bracket, box.topRight, -1, 1, stroke, length);
    _bracket(canvas, bracket, box.bottomLeft, 1, -1, stroke, length);
    _bracket(canvas, bracket, box.bottomRight, -1, -1, stroke, length);
  }

  /// One corner: two arms and an elbow that is a real arc.
  ///
  /// A quadratic fillet is not a circle, so the stroke's inner and outer edges
  /// come out with different centres — the elbow looks pinched inside. An arc of
  /// radius [bracketElbow] around the elbow's centre keeps the inner edge one
  /// stroke out, the outer two, and both concentric with the scrim's opening.
  void _bracket(
    Canvas canvas,
    Paint paint,
    Offset corner,
    int dx,
    int dy,
    double stroke,
    double length,
  ) {
    final half = stroke / 2;
    final radius = bracketElbow(stroke);
    final path = Path()
      ..moveTo(corner.dx + dx * half, corner.dy + dy * length)
      ..lineTo(corner.dx + dx * half, corner.dy + dy * (half + radius))
      ..arcToPoint(
        Offset(corner.dx + dx * (half + radius), corner.dy + dy * half),
        radius: Radius.circular(radius),
        // Up-then-right and down-then-left both turn clockwise on screen.
        clockwise: dx == dy,
      )
      ..lineTo(corner.dx + dx * length, corner.dy + dy * half);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ScanOverlayPainter oldDelegate) =>
      oldDelegate.appearing != appearing ||
      oldDelegate.dismissed != dismissed ||
      oldDelegate.target != target ||
      oldDelegate.windowFor != windowFor ||
      oldDelegate.dimOpacity != dimOpacity ||
      oldDelegate.accent != accent;
}
