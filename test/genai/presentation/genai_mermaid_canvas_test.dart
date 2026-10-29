import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_mermaid_view.dart';

const eulerSieve = '''
flowchart TD
  A[Input n] --> B[Initialize visited array false and primes list empty]
  B --> C{Loop i from 2 to n}
  C -->|i unvisited| D[Add i to primes]
  C -->|i visited| E{Loop p in primes}
  D --> E
  E --> F[Set x to i times p]
  F --> G{x <= n}
  G -->|yes| H[Mark x visited]
  H --> I{i mod p equals 0}
  I -->|yes| J[Break inner loop]
  I -->|no| E
  G -->|no| J
  J --> C
  C -->|finished| K[Output primes]
''';

void main() {
  for (final direction in ['TD', 'LR']) {
    testWidgets('$direction canvas remains readable and fullscreen can reach every node',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final code = eulerSieve.replaceFirst('flowchart TD', 'flowchart $direction');
      for (final width in [320.0, 768.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MaterialApp(
            theme: width == 768 ? ThemeData.dark() : ThemeData.light(),
            home: Scaffold(
              appBar: AppBar(title: const Text('TechPie shell')),
              body: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) =>
                      Scaffold(body: SingleChildScrollView(child: GenAiMermaidView(code: code))),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final canvasFinder = find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is FlowchartPainter,
        );
        final painter = tester.widget<CustomPaint>(canvasFinder).painter! as FlowchartPainter;
        final canvas = tester.renderObject<RenderBox>(canvasFinder);
        // The renderer must receive its full natural canvas before fitting;
        // checking only that a Mermaid widget exists missed the original bug.
        for (final node in painter.diagram.nodes) {
          expect(node.x + node.width, lessThanOrEqualTo(canvas.size.width + .01));
          expect(node.y + node.height, lessThanOrEqualTo(canvas.size.height + .01));
        }
        void expectPanBounded() {
          final active = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
          final box = tester.renderObject<RenderBox>(canvasFinder);
          final scale = active.transformationController!.value.getMaxScaleOnAxis();
          // The white canvas includes the 24px edge/arrowhead padding.
          final content = Rect.fromPoints(
            box.localToGlobal(Offset.zero),
            box.localToGlobal(box.size.bottomRight(Offset.zero)),
          ).inflate(24 * scale);
          final viewport = tester.getRect(find.byType(InteractiveViewer));
          void checkAxis(double start, double end, double viewStart, double viewEnd) {
            if (end - start <= viewEnd - viewStart + .01) {
              expect((start + end) / 2, closeTo((viewStart + viewEnd) / 2, .01));
            } else {
              expect(start, lessThanOrEqualTo(viewStart + .01));
              expect(end, greaterThanOrEqualTo(viewEnd - .01));
            }
          }

          checkAxis(content.left, content.right, viewport.left, viewport.right);
          checkAxis(content.top, content.bottom, viewport.top, viewport.bottom);
        }

        Future<void> dragPastEdges() async {
          for (final offset in [const Offset(4000, 4000), const Offset(-4000, -4000)]) {
            await tester.drag(find.byType(InteractiveViewer), offset);
            await tester.pumpAndSettle();
            expectPanBounded();
          }
        }

        final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
        void expectFits() {
          final viewport = tester.getRect(find.byType(InteractiveViewer)).inflate(.01);
          expect(viewport.contains(canvas.localToGlobal(Offset.zero)), isTrue);
          expect(
            viewport.contains(canvas.localToGlobal(canvas.size.bottomRight(Offset.zero))),
            isTrue,
          );
        }

        expect(
          viewer.transformationController!.value.getMaxScaleOnAxis(),
          greaterThanOrEqualTo(.65),
        );
        if (direction == 'TD') {
          expect(tester.getSize(find.byType(InteractiveViewer)).height, greaterThan(380));
        }
        await tester.tap(find.byTooltip('适应窗口'));
        await tester.pumpAndSettle();
        expectFits();
        await dragPastEdges();
        expectFits();
        viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
        await tester.pump();
        await tester.drag(find.byType(InteractiveViewer), const Offset(-40, -40));
        await tester.pumpAndSettle();
        expect(viewer.transformationController!.value.getMaxScaleOnAxis(), greaterThan(1));
        await dragPastEdges();
        await tester.tap(find.byTooltip('适应窗口'));
        await tester.pumpAndSettle();
        expectFits();
        await tester.tap(find.byTooltip('全屏查看'));
        await tester.pumpAndSettle();
        expect(find.text('TechPie shell'), findsNothing);
        final fullViewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
        final fullController = fullViewer.transformationController!;
        final beforeZoom = fullController.value.getMaxScaleOnAxis();
        await tester.tap(find.byTooltip('放大'));
        await tester.pumpAndSettle();
        expect(fullController.value.getMaxScaleOnAxis(), greaterThan(beforeZoom));
        final center = tester.getCenter(find.byType(InteractiveViewer));
        final beforePinch = fullController.value.getMaxScaleOnAxis();
        final first = await tester.startGesture(center - const Offset(30, 0), pointer: 1);
        final second = await tester.startGesture(center + const Offset(30, 0), pointer: 2);
        await tester.pump();
        await first.moveTo(center - const Offset(60, 0));
        await second.moveTo(center + const Offset(60, 0));
        await tester.pump();
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
        expect(fullController.value.getMaxScaleOnAxis(), greaterThan(beforePinch));
        final beforePan = fullController.value.clone();
        await tester.drag(find.byType(InteractiveViewer), const Offset(-80, -120));
        await tester.pumpAndSettle();
        expect(fullController.value, isNot(beforePan));
        final zoomBeforeResize = fullController.value.getMaxScaleOnAxis();
        tester.view.physicalSize = Size(width + 40, 850);
        await tester.pumpAndSettle();
        expect(fullController.value.getMaxScaleOnAxis(), closeTo(zoomBeforeResize, .001));
        expectPanBounded();
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        await dragPastEdges();
        await tester.tap(find.byTooltip('缩小'));
        await tester.pumpAndSettle();
        expectPanBounded();
        await tester.tap(find.byTooltip('适应窗口'));
        await tester.pumpAndSettle();
        final fullCanvas = tester.renderObject<RenderBox>(canvasFinder);
        final viewport = tester.getRect(find.byType(InteractiveViewer)).inflate(.01);
        expect(viewport.contains(fullCanvas.localToGlobal(Offset.zero)), isTrue);
        expect(
          viewport.contains(fullCanvas.localToGlobal(fullCanvas.size.bottomRight(Offset.zero))),
          isTrue,
        );
        // Rotation / desktop resize keeps the full canvas available.
        tester.view.physicalSize = Size(900, width);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('适应窗口'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byTooltip('全屏查看'), findsOneWidget);
        expectPanBounded();
        await tester.tap(find.byTooltip('查看源码'));
        await tester.pumpAndSettle();
        expect(find.text(code), findsOneWidget);
        await tester.tap(find.byTooltip('切换到图表'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
