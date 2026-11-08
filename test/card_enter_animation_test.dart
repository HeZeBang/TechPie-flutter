import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/swipeable_card.dart';

void main() {
  // Regression: the deadlines list jumped during the bounce back from its
  // bottom edge. Cards that had scrolled out of the cache extent were
  // re-mounted on the way back and replayed their enter animation from zero
  // height, shifting everything below them.
  testWidgets('bounce back from the bottom settles at the end without a jump',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            physics: const BouncingScrollPhysics(),
            children: [
              for (var i = 0; i < 40; i++)
                CardEnterAnimation(
                  key: ValueKey(i),
                  child: SizedBox(height: 140, child: Text('card $i')),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(ListView)));
    for (var i = 0; i < 160; i++) {
      await gesture.moveBy(const Offset(0, -35));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();

    final position = controller.position;
    final end = position.maxScrollExtent;
    expect(position.pixels, greaterThan(end), reason: 'overscrolled past end');

    var lowest = position.pixels;
    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (position.pixels < lowest) lowest = position.pixels;
      expect(position.maxScrollExtent, end, reason: 'extent changed');
    }
    expect(lowest, greaterThanOrEqualTo(end - 1));
    expect(position.pixels, moreOrLessEquals(end, epsilon: 1));
  });
}
