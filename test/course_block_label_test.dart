import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/course_block_label.dart';

void main() {
  // The block's height is the periods it spans (100px each, minus 4), its
  // width a day column. Before CourseBlockLabel the name took 70%, the
  // location 20% and the teachers two lines on top, which overflowed for a
  // long name + teacher + wrapping location in a narrow column.
  const heights = [12.0, 36.0, 46.0, 96.0, 146.0, 196.0, 296.0];
  const widths = [36.0, 48.0, 64.0, 120.0];
  const scales = [1.0, 1.3, 2.0];

  for (final scale in scales) {
    testWidgets('no overflow at text scale $scale', (tester) async {
      for (final h in heights) {
        for (final w in widths) {
          for (final custom in [false, true]) {
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: CourseBlockLabel(
                        name: 'Introduction to Current Life Science D(BIO1001)',
                        color: Colors.black,
                        time: custom ? '08:15–09:55' : null,
                        teachers: 'danyibing',
                        location: '教学中心101',
                      ),
                    ),
                  ),
                ),
              ),
            );
            final error = tester.takeException();
            expect(error, isNull, reason: 'h=$h w=$w custom=$custom: $error');
          }
        }
      }
    });
  }

  testWidgets('a roomy block shows every part', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 196,
            child: CourseBlockLabel(
              name: 'Linear Algebra',
              color: Colors.black,
              teachers: 'danyibing',
              location: '教学中心101',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Linear Algebra'), findsOneWidget);
    expect(find.text('danyibing'), findsOneWidget);
    expect(find.text('教学中心101'), findsOneWidget);
  });
}
