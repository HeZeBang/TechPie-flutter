import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/theme/theme.dart';
import 'package:techpie/utils/motion.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:techpie/widgets/desktop_popup.dart';
import 'package:techpie/widgets/desktop_select_popover.dart';
import 'package:techpie/widgets/swipeable_card.dart';

void main() {
  test('TgMotion.rubberBand is strictly monotonic and asymptotically bounded',
      () {
    expect(TgMotion.rubberBand(0), 0);
    expect(TgMotion.rubberBand(-0.5), 0);
    final a = TgMotion.rubberBand(0.1, limit: 0.26);
    final b = TgMotion.rubberBand(0.5, limit: 0.26);
    final c = TgMotion.rubberBand(10.0, limit: 0.26);
    expect(a, greaterThan(0));
    expect(b, greaterThan(a));
    expect(c, greaterThan(b));
    expect(c, lessThan(0.26));
  });

  testWidgets(
      'TpPressScale shrinks on press, springs back on release, cancels on drag, and respects disableAnimations',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: TpPressScale(
              pressedScale: 0.94,
              child: SizedBox(
                key: ValueKey('press-target'),
                width: 120,
                height: 48,
              ),
            ),
          ),
        ),
      ),
    );

    double currentScale() {
      final transforms = find.descendant(
        of: find.byType(TpPressScale),
        matching: find.byType(Transform),
      );
      if (transforms.evaluate().isEmpty) return 1.0;
      return tester.widget<Transform>(transforms).transform.storage[0];
    }

    expect(currentScale(), closeTo(1.0, 0.001));

    final center = tester.getCenter(find.byKey(const ValueKey('press-target')));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(currentScale(), lessThan(0.96));

    // Dragging beyond kTouchSlop cancels press scale immediately (scroll safe).
    await gesture.moveBy(const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(currentScale(), closeTo(1.0, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();

    // Normal press and release springs cleanly back to 1.0.
    final tap = await tester.startGesture(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(currentScale(), lessThan(0.96));
    await tap.up();
    await tester.pumpAndSettle();
    expect(currentScale(), closeTo(1.0, 0.01));

    // Reduced-motion mode bypasses Transform entirely.
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: TpPressScale(
                pressedScale: 0.94,
                child: SizedBox(
                  key: ValueKey('press-target'),
                  width: 120,
                  height: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(TpPressScale),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'SwipeableCard triggers selection haptic on threshold crossing and success haptic on right-swipe commit',
    (tester) async {
      const channel = MethodChannel('techpie/feedback');
      final played = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          if (call.method == 'play') {
            final args = (call.arguments as Map).cast<String, Object?>();
            played.add(args['id']! as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      var completedCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: SwipeableCard(
                  startAction: const SwipeAction(
                    icon: Icons.check,
                    label: '标记完成',
                    background: Colors.green,
                    foreground: Colors.white,
                  ),
                  endAction: const SwipeAction(
                    icon: Icons.delete,
                    label: '删除',
                    background: Colors.red,
                    foreground: Colors.white,
                  ),
                  onStartSwipe: () => completedCount++,
                  child: const SizedBox(
                    key: ValueKey('swipe-row'),
                    height: 64,
                    child: Center(child: Text('HW 1')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Drag past 0.32 threshold (320 * 0.45 = 144px) and release.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('swipe-row'))),
      );
      await gesture.moveBy(const Offset(150, 0));
      await tester.pump();
      expect(played, contains('selection'));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(completedCount, 1);
      expect(played, contains('success'));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
      'showDesktopPopover and DesktopSelectPopover render TgGlass BackdropFilter with spring motion and dismiss cleanly on Escape',
      (tester) async {
    String selected = 'A';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: [TpColors.light()]),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (anchorContext) => ElevatedButton(
                      onPressed: () => showDesktopPopover(
                        anchorContext: anchorContext,
                        builder: (context, close) => DesktopPopoverSurface(
                          child: DesktopMenuRow(
                            leading: const Icon(TpIcons.check),
                            title: const Text('浮层选项'),
                            selected: true,
                            onTap: close,
                          ),
                        ),
                      ),
                      child: const Text('打开浮层'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  DesktopSelectPopover<String>(
                    items: const ['A', 'B', 'C'],
                    value: selected,
                    onChanged: (v) => setState(() => selected = v),
                    labelBuilder: (v) => '项 $v',
                    anchorBuilder: (_, __, toggle) => ElevatedButton(
                      onPressed: toggle,
                      child: Text('当前 $selected'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 1. showDesktopPopover uses DesktopPopoverMotion + BackdropFilter + Esc.
    await tester.tap(find.text('打开浮层'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopPopoverMotion), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('浮层选项'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('浮层选项'), findsNothing);

    // 2. DesktopSelectPopover uses DesktopPopoverMotion + BackdropFilter + Esc.
    await tester.tap(find.text('当前 A'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopPopoverMotion), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('项 B'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('项 B'), findsNothing);
  });
}
