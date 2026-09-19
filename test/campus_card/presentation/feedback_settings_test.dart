import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/domain/models/feedback_models.dart';
import 'package:techpie/features/campus_card/presentation/screens/settings_screen.dart';

void main() {
  testWidgets(
      'each feedback scenario has independent enabled-by-default controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final runtime = await buildDemoRuntime();
    addTearDown(runtime.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final scenario in FeedbackScenario.values) {
      for (final channel in FeedbackChannel.values) {
        if (scenario == FeedbackScenario.interaction &&
            channel == FeedbackChannel.sound) {
          continue;
        }
        final control =
            find.byKey(ValueKey('feedback-${scenario.name}-${channel.name}'));
        await tester.scrollUntilVisible(control, 160);
        expect(
          tester
              .widget<Switch>(
                find.descendant(of: control, matching: find.byType(Switch)),
              )
              .value,
          isTrue,
        );
      }
    }

    final sound = find.byKey(const ValueKey('feedback-paymentSuccess-sound'));
    await tester.scrollUntilVisible(sound, -160);
    await tester.tap(sound);
    await tester.pumpAndSettle();
    final success =
        await runtime.feedback.settingsFor(FeedbackScenario.paymentSuccess);
    final offline = await runtime.feedback
        .settingsFor(FeedbackScenario.networkDisconnected);
    expect(success.sound, isFalse);
    expect(success.vibration, isTrue);
    expect(offline.sound, isTrue);
    expect(offline.vibration, isTrue);
  });
}
