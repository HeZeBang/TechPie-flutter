import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';

void main() {
  test('GenAI uses the draft drawer and modal scrims', () {
    expect(genAiOverlayScrim(drawer: true), const Color(0x55121015));
    expect(genAiOverlayScrim(), const Color(0x66121015));
  });

  testWidgets('dialog blurs only its barrier and preserves the result and dismissal',
      (tester) async {
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  result = await genAiShowDialog<int>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => Dialog(
                      child: TextButton(
                        key: const ValueKey('overlay-content'),
                        onPressed: () => Navigator.pop(context, 7),
                        child: const Text('Finish'),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('overlay-content'));
    final route = ModalRoute.of(tester.element(content))!;
    expect(route, isA<DialogRoute<int>>());
    expect(route.barrierColor, const Color(0x66121015));
    expect(route.barrierDismissible, isFalse);
    expect(route.filter, ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3));
    expect(
      find.byWidgetPredicate((widget) => widget is BackdropFilter && widget.filter == route.filter),
      findsOneWidget,
    );
    // The filter is attached to the barrier, not around the dialog itself.
    expect(find.ancestor(of: content, matching: find.byType(BackdropFilter)), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(content, findsOneWidget);
    await tester.tap(content);
    await tester.pumpAndSettle();
    expect(result, 7);
    expect(content, findsNothing);
  });

  testWidgets('modal sheet shares the blurred scrim and stays barrier dismissible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => genAiShowModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  showDragHandle: false,
                  builder: (_) => const SizedBox(
                    key: ValueKey('overlay-content'),
                    height: 100,
                    child: Center(child: Text('Sheet')),
                  ),
                ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('overlay-content'));
    final route = ModalRoute.of(tester.element(content))!;
    expect(route, isA<ModalBottomSheetRoute<void>>());
    expect(route.barrierColor, const Color(0x66121015));
    expect(route.barrierDismissible, isTrue);
    expect(route.filter, ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3));
    expect(find.ancestor(of: content, matching: find.byType(BackdropFilter)), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is BackdropFilter && widget.filter == route.filter),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(content, findsNothing);
  });

  testWidgets('shared dialog frame keeps the draft header and nullable close result',
      (tester) async {
    String? result = 'pending';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await genAiShowDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => GenAiDialogFrame(
                    surfaceKey: const ValueKey('frame-surface'),
                    headerKey: const ValueKey('frame-header'),
                    title: const Text('标题'),
                    content: const Text('正文'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'saved'),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('frame-header'));
    expect(tester.getSize(header).height, 72);
    expect(tester.widget<Padding>(header).padding, const EdgeInsets.fromLTRB(22, 18, 22, 18));
    expect(tester.getSize(find.byKey(const ValueKey('frame-surface'))).width, 500);
    expect(tester.getSize(find.byTooltip('关闭')), const Size(36, 36));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(header, findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, 'saved');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final atBottom in [false, true]) {
    testWidgets('anchored menu uses exact 7px clearance at ${atBottom ? 'bottom' : 'top'}',
        (tester) async {
      String? selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 400,
                child: Scaffold(
                  key: const ValueKey('menu-stage'),
                  body: Align(
                    alignment: atBottom ? Alignment.bottomRight : Alignment.topRight,
                    child: Builder(
                      builder: (context) => SizedBox(
                        key: const ValueKey('menu-anchor'),
                        width: 36,
                        height: 36,
                        child: InkWell(
                          onTap: () async {
                            selection = await genAiShowAnchoredMenu<String>(
                              context: context,
                              anchorContext: context,
                              items: const [
                                PopupMenuItem(value: 'chosen', height: 42, child: Text('Option')),
                              ],
                            );
                          },
                          child: const Text('Open'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final anchor = tester.getRect(find.byKey(const ValueKey('menu-anchor')));
      final stage = tester.getRect(find.byKey(const ValueKey('menu-stage')));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byKey(const ValueKey('genai-anchored-menu')));
      expect(menu.right, closeTo(stage.right - 10, .01));
      expect(menu.width, 220);
      expect(menu.overlaps(anchor), isFalse);
      if (atBottom) {
        expect(anchor.top - menu.bottom, closeTo(7, .01));
      } else {
        expect(menu.top - anchor.bottom, closeTo(7, .01));
      }
      await tester.tap(find.text('Option'));
      await tester.pumpAndSettle();
      expect(selection, 'chosen');
      expect(find.byKey(const ValueKey('genai-anchored-menu')), findsNothing);
    });
  }
}
