import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_select.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('an iOS display field only shows the value', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSelect(
            value: 'dark',
            useIosNativeMenu: false,
            options: const [
              AdaptiveSelectOption(value: 'system', label: 'System'),
              AdaptiveSelectOption(value: 'dark', label: 'Dark'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Dark'), findsOneWidget);
    // The caller owns the tap; the field itself presents nothing.
    expect(find.byType(CNPopupMenuButton), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native menu maps checked values and rejects invalid indices', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String value = 'system';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: AdaptiveSelect(
              useIosNativeMenu: true,
              accessibilityLabel: 'Theme',
              value: value,
              options: const [
                AdaptiveSelectOption(value: 'system', label: 'System'),
                AdaptiveSelectOption(value: 'dark', label: 'Dark'),
              ],
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    var menu = tester.widget<CNPopupMenuButton>(find.byType(CNPopupMenuButton));
    expect(menu.semanticLabel, 'Theme');
    // The list reads top to bottom wherever the menu opens.
    expect(menu.preserveTopToBottomOrder, isTrue);
    expect((menu.items.first as CNPopupMenuItem).checked, true);
    menu.onSelected(-1);
    menu.onSelected(99);
    expect(value, 'system');
    menu.onSelected(1);
    await tester.pumpAndSettle();
    menu = tester.widget<CNPopupMenuButton>(find.byType(CNPopupMenuButton));
    expect(value, 'dark');
    expect(menu.buttonLabel, 'Dark');
    expect((menu.items.last as CNPopupMenuItem).checked, true);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native menu opt-in preserves Android dropdown behavior', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSelect(
            useIosNativeMenu: true,
            value: 'system',
            options: const [
              AdaptiveSelectOption(value: 'system', label: 'System'),
              AdaptiveSelectOption(value: 'dark', label: 'Dark'),
            ],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    expect(find.byType(UiKitView), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(selected, 'dark');
    debugDefaultTargetPlatformOverride = null;
  });
}
