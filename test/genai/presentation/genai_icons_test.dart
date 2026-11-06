import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_icons.dart';

void main() {
  test('every glyph has non-empty geometry inside the 24-grid', () {
    for (final glyph in GenAiGlyph.values) {
      final path = GenAiIcon.debugPath(glyph);
      final metrics = path.computeMetrics().toList();
      expect(metrics, isNotEmpty, reason: glyph.name);
      expect(
        metrics.fold<double>(0, (sum, metric) => sum + metric.length),
        greaterThan(0),
        reason: glyph.name,
      );
      // Path.getBounds includes Bézier control points, not just the drawn
      // curve (SVG arcs can have controls beyond the viewBox). Inspect the
      // actual contours instead, including their endpoints.
      for (final metric in metrics) {
        for (var i = 0; i <= 1000; i++) {
          final point = metric.getTangentForOffset(metric.length * i / 1000)!.position;
          expect(point.dx, inInclusiveRange(0, 24), reason: glyph.name);
          expect(point.dy, inInclusiveRange(0, 24), reason: glyph.name);
        }
      }
    }
  });

  testWidgets('labelled icons expose their label; unlabelled icons expose nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: GenAiIcon(GenAiGlyph.search, semanticLabel: 'Search conversations'),
      ),
    );
    expect(find.bySemanticsLabel('Search conversations'), findsOneWidget);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: GenAiIcon(GenAiGlyph.search),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
    expect(
      tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!.childrenCount,
      0,
    );
    semantics.dispose();
  });

  testWidgets('icons inherit size, color and opacity from IconTheme', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: IconTheme(
          data: IconThemeData(size: 16, color: Color(0xffff0000), opacity: 0.5),
          child: GenAiIcon(GenAiGlyph.plus),
        ),
      ),
    );
    expect(tester.getSize(find.byType(GenAiIcon)), const Size.square(16));
    final paint = tester.widget<CustomPaint>(find.byType(CustomPaint));
    final recorder = ui.PictureRecorder();
    // Rasterize at 2× the design grid so the stroke covers the sampled
    // center pixel fully; request straight RGBA rather than premultiplied.
    paint.painter!.paint(Canvas(recorder), const Size.square(48));
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final image = await picture.toImage(48, 48);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      final pixel = bytes!.getUint32((24 * 48 + 24) * 4);
      expect((pixel >> 24) & 255, 255);
      expect((pixel >> 16) & 255, 0);
      expect((pixel >> 8) & 255, 0);
      expect(pixel & 255, closeTo(128, 1));
      image.dispose();
    });
    picture.dispose();
  });

  test('SVG parser handles absolute, relative and reflected curves', () {
    final absolute = GenAiIcon.debugParsePath(
      'M2 2L4 2H6V4C6 5 7 6 8 6S10 7 10 8Q10 9 12 9T14 9A2 2 0 0 1 16 11Z',
    );
    final relative = GenAiIcon.debugParsePath(
      'm2 2l2 0h2v2c0 1 1 2 2 2s2 1 2 2q0 1 2 1t2 0a2 2 0 0 1 2 2z',
    );
    expect(relative.getBounds(), absolute.getBounds());
    final a = absolute.computeMetrics().single;
    final b = relative.computeMetrics().single;
    expect(b.length, closeTo(a.length, 0.001));
    for (var i = 0; i < 20; i++) {
      expect(
        (b.getTangentForOffset(b.length * i / 20)!.position -
                a.getTangentForOffset(a.length * i / 20)!.position)
            .distance,
        lessThan(0.001),
      );
    }
    final implicit = GenAiIcon.debugParsePath('m2 2 2 0 0 2z');
    expect(implicit.getBounds(), const Rect.fromLTRB(2, 2, 4, 4));
  });
}
