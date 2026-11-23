import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/schedule_picker_sheet.dart';

void main() {
  testWidgets(
    'mouse drags select a time in the desktop sheet',
    (tester) async {
      const initialTime = TimeOfDay(hour: 15, minute: 14);
      TimeOfDay? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showScheduleTimePicker(
                  context: context,
                  initialTime: initialTime,
                  title: '截止时间',
                );
              },
              child: const Text('选择时间'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选择时间'));
      await tester.pumpAndSettle();

      final wheels = find.byType(CupertinoPicker);
      expect(wheels, findsNWidgets(2));
      await tester.drag(
        wheels.first,
        const Offset(0, -72),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.drag(
        wheels.last,
        const Offset(0, 72),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(selected?.hour, greaterThan(initialTime.hour));
      expect(selected?.minute, lessThan(initialTime.minute));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
