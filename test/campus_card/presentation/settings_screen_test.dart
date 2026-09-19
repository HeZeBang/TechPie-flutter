import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/core/config/payment_code_preferences.dart';
import 'package:techpie/features/campus_card/presentation/screens/settings_screen.dart';

/// 离线码优先 lives in the feature's settings tab: the user turns it off there,
/// and the choice outlives the app.
void main() {
  Future<void> pumpSettings(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets('离线码优先 defaults on and is stored when switched off', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpSettings(tester, container);

    expect(find.text('离线码优先'), findsOneWidget);
    final row = find.byKey(const Key('offline-code-first'));
    final switchFinder = find.descendant(of: row, matching: find.byType(Switch));
    expect(tester.widget<Switch>(switchFinder).value, isTrue);

    await tester.tap(switchFinder);
    await tester.pump();

    expect(container.read(offlineCodeFirstProvider).valueOrNull, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(OfflineCodeFirstController.preferenceKey),
      isFalse,
      reason: 'the choice must survive the process',
    );
  });

  testWidgets('a stored choice is what the switch shows', (tester) async {
    SharedPreferences.setMockInitialValues({
      OfflineCodeFirstController.preferenceKey: false,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpSettings(tester, container);

    final row = find.byKey(const Key('offline-code-first'));
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: row, matching: find.byType(Switch)),
          )
          .value,
      isFalse,
    );
  });
}
