import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/adaptive_layout.dart';
import 'package:techpie/widgets/app_shell/app_shell_metrics.dart';

void main() {
  test('window size classes use stable navigation breakpoints', () {
    expect(appWindowSizeClassFor(599), AppWindowSizeClass.compact);
    expect(appWindowSizeClassFor(600), AppWindowSizeClass.medium);
    expect(appWindowSizeClassFor(959), AppWindowSizeClass.medium);
    expect(appWindowSizeClassFor(960), AppWindowSizeClass.expanded);
  });

  testWidgets('shell metrics expose navigation obstruction to page content', (
    WidgetTester tester,
  ) async {
    late double bottomPadding;

    await tester.pumpWidget(
      MaterialApp(
        home: AppShellMetrics(
          bottomObstruction: 83,
          child: Builder(
            builder: (context) {
              bottomPadding = AppShellMetrics.bottomContentPaddingOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(bottomPadding, 99);
  });
}
