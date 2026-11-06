import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_markdown.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_view.dart';

/// Both answers end without a closing fence so the visual stays incomplete and
/// never starts a platform view; the header still proves the builder wiring.
const _titled = '说明\n\n```techpie-visual {"title":"曲线与切线"}\n'
    '<!doctype html><html><body><p>x</p></body></html>\n';

const _bare = '说明\n\n```techpie-visual\n'
    '<!doctype html><html><body><p>x</p></body></html>\n';

void main() {
  Future<void> pump(WidgetTester tester, String data) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GenAiMarkdown(data: data, interactiveVisuals: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('builder carries the fence title into the visual card', (tester) async {
    await pump(tester, _titled);

    final view = tester.widget<GenAiVisualView>(find.byType(GenAiVisualView));
    expect(view.title, '曲线与切线');
    expect(view.complete, false);

    expect(find.text('曲线与切线'), findsOneWidget);
    expect(find.text('交互示例'), findsNothing);
  });

  testWidgets('an old bare fence shows only the generic tag', (tester) async {
    await pump(tester, _bare);

    final view = tester.widget<GenAiVisualView>(find.byType(GenAiVisualView));
    expect(view.title, isNull);
    expect(view.complete, false);
    expect(find.text('曲线与切线'), findsNothing);

    expect(find.text('交互示例'), findsOneWidget);
  });
}
