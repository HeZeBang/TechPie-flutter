import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_select.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS select uses a composited Cupertino action sheet', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String? selectedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSelect(
            value: 'system',
            options: const [
              AdaptiveSelectOption(value: 'system', label: 'System'),
              AdaptiveSelectOption(value: 'dark', label: 'Dark'),
            ],
            onChanged: (value) => selectedValue = value,
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(selectedValue, 'dark');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'native menu follows selection and appearance and validates events',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final selection = ValueNotifier('system');
    addTearDown(selection.dispose);
    final updates = <Map<Object?, Object?>>[];
    final selections = <String>[];
    const channel = MethodChannel('techpie/native_select/986');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expect(call.method, 'updateConfiguration');
      updates.add(call.arguments as Map<Object?, Object?>);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(
      ValueListenableBuilder<String>(
        valueListenable: selection,
        builder: (_, value, __) => MaterialApp(
          theme: value == 'system' ? ThemeData.light() : ThemeData.dark(),
          home: Scaffold(
            body: AdaptiveSelect(
              useIosNativeMenu: true,
              accessibilityLabel: 'Theme',
              value: value,
              options: const [
                AdaptiveSelectOption(
                  value: 'system',
                  label: 'System',
                  sfSymbol: 'circle.lefthalf.filled',
                ),
                AdaptiveSelectOption(
                  value: 'dark',
                  label: 'Dark',
                  sfSymbol: 'moon',
                ),
              ],
              onChanged: (value) {
                selections.add(value);
                selection.value = value;
              },
            ),
          ),
        ),
      ),
    );
    final viewFinder = find.byType(UiKitView);
    final view = tester.widget<UiKitView>(viewFinder);
    final state = tester.state(viewFinder);
    expect(view.viewType, 'techpie/native_select');
    final configuration = view.creationParams! as Map<String, Object?>;
    expect(configuration['value'], 'system');
    expect(configuration['accessibilityLabel'], 'Theme');
    expect(configuration['options'], [
      {
        'value': 'system',
        'label': 'System',
        'sfSymbol': 'circle.lefthalf.filled',
      },
      {'value': 'dark', 'label': 'Dark', 'sfSymbol': 'moon'},
    ]);
    view.onPlatformViewCreated!(986);
    await tester.pump();

    Future<void> sendSelection(String value) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('onChanged', {'value': value})),
        (_) {},
      );
    }

    await sendSelection('dark');
    await tester.pumpAndSettle();
    expect(selections, ['dark']);
    expect(updates.last['value'], 'dark');
    expect(updates.last['brightness'], 'dark');
    expect(tester.state(viewFinder), same(state));

    await sendSelection('removed-option');
    await tester.pump();
    expect(selections, ['dark']);
    expect(find.byType(CupertinoActionSheet), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native menu opt-in preserves Android dropdown behavior',
      (tester) async {
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
