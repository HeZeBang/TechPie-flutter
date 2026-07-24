import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/adaptive_motion.dart';

void main() {
  testWidgets('system Reduce Motion disables app animation durations', (
    WidgetTester tester,
  ) async {
    Duration? effectiveDuration;
    bool? animationsEnabled;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Builder(
              builder: (context) {
                animationsEnabled = appAnimationsEnabled(context);
                effectiveDuration = appAnimationDuration(
                  context,
                  const Duration(milliseconds: 350),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    expect(animationsEnabled, isFalse);
    expect(effectiveDuration, Duration.zero);
  });
}
