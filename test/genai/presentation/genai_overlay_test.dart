import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';

void main() {
  testWidgets('modal sheet stays barrier dismissible', (tester) async {
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
    expect(content, findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(content, findsNothing);
  });

  testWidgets('dialog requires an explicit action and returns its result', (tester) async {
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
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('标题'), findsOneWidget);
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
    testWidgets(
      'anchored menu stays within the workspace and clears its anchor at ${atBottom ? 'bottom' : 'top'}',
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
        expect(stage.contains(menu.topLeft), isTrue);
        expect(stage.contains(menu.bottomRight), isTrue);
        expect(menu.overlaps(anchor), isFalse);
        if (atBottom) {
          expect(menu.bottom, lessThan(anchor.top));
        } else {
          expect(menu.top, greaterThan(anchor.bottom));
        }
        await tester.tap(find.text('Option'));
        await tester.pumpAndSettle();
        expect(selection, 'chosen');
        expect(find.byKey(const ValueKey('genai-anchored-menu')), findsNothing);
      },
    );
  }
}
