import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';
import 'package:techpie/features/campus_card/presentation/scanner/six_digit_password_panel.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    'autosubmits once six digits are pressed, with the exact string',
    (tester) async {
      var submitted = '';
      await tester.pumpWidget(
        _host(
          SixDigitPasswordPanel(
            onSubmit: (v) => submitted = v,
            onCancel: () {},
          ),
        ),
      );

      for (final key in ['1', '2', '3', '4', '5']) {
        await tester.tap(find.text(key));
        await tester.pump();
      }
      expect(
        submitted,
        isEmpty,
        reason: 'no submit may fire before six digits',
      );

      await tester.tap(find.text('6'));
      await tester.pump();
      expect(submitted, '123456');
    },
  );

  testWidgets('digit semantics report entered count and delete backspaces', (
    tester,
  ) async {
    var submitted = '';
    await tester.pumpWidget(
      _host(
        SixDigitPasswordPanel(onSubmit: (v) => submitted = v, onCancel: () {}),
      ),
    );

    await tester.tap(find.text('9'));
    await tester.pump();
    expect(find.byKey(const Key('password-dot-0-true')), findsOneWidget);

    await tester.tap(find.byKey(const Key('password-key-delete')));
    await tester.pump();
    expect(find.byKey(const Key('password-dot-0-false')), findsOneWidget);
    expect(submitted, isEmpty);
  });

  testWidgets('key press changes immediately and emits selection feedback', (
    tester,
  ) async {
    final feedback = InMemoryFeedbackPort();
    await tester.pumpWidget(
      _host(
        SixDigitPasswordPanel(
          feedback: feedback,
          onSubmit: (_) {},
          onCancel: () {},
        ),
      ),
    );
    final surface = find.byKey(const Key('password-key-1-surface'));
    final normalColor = tester.widget<ColoredBox>(surface).color;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('password-key-1'))),
    );
    await tester.pump();

    expect(tester.widget<ColoredBox>(surface).color, isNot(normalColor));
    expect(feedback.events, [FeedbackEvent.selection]);

    await gesture.up();
    await tester.pump();
    expect(tester.widget<ColoredBox>(surface).color, normalColor);
  });
}
